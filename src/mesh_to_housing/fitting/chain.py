from dataclasses import dataclass, replace
from typing import Literal, Optional, Sequence

import numpy as np

from ..geometry.paths import Path
from ..geometry.rotations import side_and_up, unit
from ..items.item import Item
from ..items.shape import Pose
from ..placement import Placement

Anchor = Literal["middle", "outer"]


@dataclass(frozen=True, eq=False)
class Link:
    """What every segment of a chain is, and how its segments join.

    Each segment is the item laid along its own span: the pose says which of the item's axes runs along the span
    and which side faces the segment's up, so segments turn with the chain. A "middle" anchor centers a segment on
    its span, and an "outer" anchor puts its up side on the span, as for rows on the target surface. Segments are
    laid to overlap the next one by overlap of their length, and stay joined while they overlap by at most
    max_overlap and bend by at most max_bend degrees.
    """

    item: Item
    pose: Pose
    anchor: Anchor
    overlap: float
    max_bend: float
    max_overlap: float

    def placed(self, start: np.ndarray, end: np.ndarray, up: np.ndarray, scale: float) -> Placement:
        """The item laid from start to end, turned toward up, with its anchor halfway between them."""
        along = unit(end - start)
        frame = np.column_stack((along, *side_and_up(along, up)))
        point = {"middle": self.pose.middle, "outer": self.pose.outer_middle}[self.anchor]
        return Placement.with_point_at(self.item, point, (start + end) / 2, frame @ self.pose.axes.T, scale)


class Chain:
    """Copies of one item laid end to end along a line of joints.

    Segment i runs from joint i to joint i + 1 and reaches a little past both joints, so neighbors overlap there and
    the chain has no gaps where it bends. Its up side faces ups[i].
    """

    def __init__(self, link: Link, joints: np.ndarray, ups: np.ndarray, scales: np.ndarray,
                 placements: Optional[Sequence[Optional[Placement]]] = None):
        self.link = link
        self.joints = _frozen(joints, (-1, 3))
        self.ups = _frozen(ups, (-1, 3))
        self.scales = _frozen(scales, (-1,))
        placements = [None] * len(self.scales) if placements is None else placements
        self.placements = tuple(
            link.placed(self.joints[index], self.joints[index + 1], self.ups[index], float(self.scales[index]))
            if placement is None else placement for index, placement in enumerate(placements))

    def __len__(self) -> int:
        return len(self.scales)

    @property
    def lengths(self) -> np.ndarray:
        """How long each segment is along its chain."""
        return self.link.pose.length * self.scales

    @property
    def spans(self) -> np.ndarray:
        return np.linalg.norm(np.diff(self.joints, axis=0), axis=1)

    @property
    def directions(self) -> np.ndarray:
        """The direction of each span, from its first joint to its second."""
        steps = np.diff(self.joints, axis=0)
        return steps / np.maximum(np.linalg.norm(steps, axis=1, keepdims=True), 1e-12)

    def bends(self) -> np.ndarray:
        """The angle by which the chain turns at each joint between two segments."""
        directions = self.directions
        cosines = np.einsum("ij,ij->i", directions[:-1], directions[1:])
        return np.degrees(np.arccos(np.clip(cosines, -1.0, 1.0)))

    def is_whole(self) -> bool:
        """Whether every joint holds: no segment falls short of its joints, and none overlaps its neighbors or bends
        more than its link allows.
        """
        ratios = self.spans / self.lengths
        if np.any(ratios > 1.0 + 1e-9) or np.any(ratios < 1.0 - self.link.max_overlap):
            return False
        return len(self) < 2 or float(self.bends().max()) <= self.link.max_bend

    def part(self, start: int, stop: int) -> "Chain":
        """The segments from start up to stop as a chain of their own, with the same placements."""
        return Chain(self.link, self.joints[start:stop + 1], self.ups[start:stop], self.scales[start:stop],
                     self.placements[start:stop])

    def changed(self, joints: Optional[np.ndarray] = None, ups: Optional[np.ndarray] = None,
                scales: Optional[np.ndarray] = None) -> "Chain":
        """The chain with new joints, ups or scales, which may also add or drop segments. Segments that stay as they
        were keep their placements.
        """
        joints = self.joints if joints is None else joints
        ups = self.ups if ups is None else ups
        scales = self.scales if scales is None else scales
        kept = dict(zip(_segment_keys(self.joints, self.ups, self.scales), self.placements))
        return Chain(self.link, joints, ups, scales, [kept.get(key) for key in _segment_keys(joints, ups, scales)])

    def relaid(self, scales: np.ndarray) -> "Chain":
        """The chain with new segment scales, laid again along its own line from its middle joint outward, so the
        middle stays where it is and the spans fit the new lengths.
        """
        scales = np.asarray(scales, dtype=float)
        spans = self.link.pose.length * scales * (1.0 - self.link.overlap)
        path = Path(self.joints)
        middle = len(self) // 2
        at = path.starts[middle] + np.concatenate(([0.0], np.cumsum(spans[middle:])))
        before = path.starts[middle] - np.cumsum(spans[:middle][::-1])[::-1]
        return self.changed(joints=path.at(np.concatenate((before, at))), scales=scales)


@dataclass(frozen=True, eq=False)
class ChainGroup:
    """A chain and the copies of it that are placed, moved and cut together with it. A plain group has no copies."""

    primary: Chain
    copies: tuple[Chain, ...] = ()

    @property
    def members(self) -> tuple[Chain, ...]:
        return (self.primary, *self.copies)

    @property
    def placements(self) -> tuple[Placement, ...]:
        return tuple(placement for chain in self.members for placement in chain.placements)

    @property
    def placements_by_segment(self) -> list[list[Placement]]:
        """For each segment of the chain, that segment of every member."""
        return [[chain.placements[index] for chain in self.members] for index in range(len(self.primary))]

    @property
    def may_split(self) -> bool:
        """Whether the chain may break into parts."""
        return True

    def with_primary(self, primary: Chain) -> Optional["ChainGroup"]:
        """The group around a changed chain, or None if the changed chain can't be placed."""
        return ChainGroup(primary)

    def part(self, start: int, stop: int) -> "ChainGroup":
        """The group cut to the segments from start up to stop."""
        return replace(self, primary=self.primary.part(start, stop),
                       copies=tuple(chain.part(start, stop) for chain in self.copies))

    def copies_of(self, placement: Placement) -> list[Placement]:
        """A single placement that leaves the chain, with the copies the group would place with it."""
        return [placement]


def _frozen(values, shape: tuple[int, ...]) -> np.ndarray:
    array = np.array(values, dtype=float).reshape(shape)
    array.flags.writeable = False
    return array


def _segment_keys(joints: np.ndarray, ups: np.ndarray, scales: np.ndarray) -> list[bytes]:
    """A key for each segment that is the same exactly when the segment is placed the same."""
    joints = np.asarray(joints, dtype=float).reshape(-1, 3)
    rows = np.column_stack((joints[:-1], joints[1:], np.asarray(ups, dtype=float).reshape(-1, 3),
                            np.asarray(scales, dtype=float).reshape(-1)))
    # Adding zero turns -0.0 into 0.0, which places a segment the same.
    return [row.tobytes() for row in rows + 0.0]
