from abc import abstractmethod
from typing import Annotated, Literal, NamedTuple, Optional, Sequence

import numpy as np
from pydantic import Field

from ...geometry.cells import CellKeys, cell_indices, cell_keys, contains_sorted
from ...geometry.coverage import uncovered_surface_keys
from ...geometry.paths import Path, medial_path, surface_path
from ...geometry.rotations import angle_between, unit
from ...geometry.settings import PathSettings, SurfaceSettings
from ...geometry.voxel_grid import VoxelGrid
from ...items.item import Item
from ...items.shape import Pose
from ...placement import Placement
from ...task import FittingTask
from ...utils.values import Fraction, NonNegativeInt, PositiveInt
from ..chain import Anchor, Chain, Link
from .base import ProposalSource, sample_positions


class ChainSource(ProposalSource):
    """Proposes whole chains. Used as a plain proposal source, it offers their segments one by one."""

    @abstractmethod
    def propose_chains(self, task: FittingTask, placements: Sequence[Placement],
                       rng: np.random.Generator) -> list[Chain]:
        pass

    def propose(self, task, placements, rng):
        return [placement for chain in self.propose_chains(task, placements, rng) for placement in chain.placements]


class ChainLayout(PathSettings):
    """Lays chains along a path, growing both ways from a seed.
    Each segment is the biggest item that still fits inside the target without crowding placed items. A chain
    stops where the next segment would turn too sharply, change size too much, or run out of room.
    """

    segments: PositiveInt = 8
    overlap: Annotated[float, Field(ge=0, lt=0.5)] = 0.1
    max_overlap: Annotated[float, Field(ge=0, lt=1)] = 0.35
    max_bend: Annotated[float, Field(gt=0, le=90)] = 30.0
    taper: Annotated[float, Field(ge=1, allow_inf_nan=False)] = 1.5
    fit: Fraction = 0.9
    crowding: Fraction = 0.5
    sizes: Annotated[tuple[Annotated[float, Field(gt=0, le=1)], ...], Field(min_length=1)] = (1.0, 0.5)
    scale_steps: PositiveInt = 4

    @abstractmethod
    def allows(self, pose: Pose) -> bool:
        pass

    def poses(self, item: Item) -> list[Pose]:
        shape = item.shape
        # Poses with the item's own thin side up go first, so they win among poses that measure the same.
        ordered = sorted(shape.poses, key=lambda pose: -round(abs(float(pose.axes[:, 2] @ shape.axes[:, 2])), 6))
        kinds = {}
        for pose in ordered:
            if pose.thickness <= min(pose.length, pose.width) + 1e-9 and self.allows(pose):
                measures = (pose.length, pose.width, pose.thickness, pose.end_contact, pose.side_contact)
                kinds.setdefault(tuple(np.round(measures, 6)), pose)
        return list(kinds.values())

    def ladder(self, task: FittingTask) -> np.ndarray:
        """Allowed scales, biggest first."""
        low, high = task.constraints.scale_bounds
        count = int(np.floor(np.log2(high / low) * self.scale_steps + 1e-9)) + 1
        return high * 2.0 ** (-np.arange(count) / self.scale_steps)

    def up_at(self, grid: VoxelGrid, path: Path, distance: float, span: float,
              previous: Optional[np.ndarray]) -> np.ndarray:
        """Which way a segment's up side faces. By default it's the path's normal, for paths over a surface."""
        return path.normal_at(distance + span / 2)

    def has_room(self, grid: VoxelGrid, link: Link, placement: Placement) -> bool:
        """An extra check a source can add on top of fits."""
        return True

    def fits(self, grid: VoxelGrid, placement: Placement, filled: CellKeys) -> bool:
        keys = cell_keys(grid.indices_of(placement.world_points(placement.item.shape.samples)))
        return np.mean(grid.near_target(keys)) >= self.fit and np.mean(contains_sorted(filled, keys)) <= self.crowding

    def laid(self, task: FittingTask, grid: VoxelGrid, path_grid: VoxelGrid, item: Item, path: Path, seed: float,
             filled: CellKeys, anchor: Anchor) -> list[Chain]:
        """The item's chains grown from seed along the path, one per pose and size, skipping repeats."""
        ladder = self.ladder(task)
        chains = []
        for pose in self.poses(item):
            layout = self.layout(grid, path_grid, Link(item, pose, anchor, self.overlap, self.max_bend,
                                                       self.max_overlap), filled)
            sized = []
            for size in self.sizes:
                cap = ladder[0] if not sized else size * sized[0].scales.max()
                scales = ladder[ladder <= cap * (1 + 1e-9)]
                chain = layout.grown(path, seed, scales) if len(scales) else None
                if chain is not None and not any(np.array_equal(chain.scales, other.scales) for other in sized):
                    sized.append(chain)
            chains.extend(sized)
        return chains

    def layout(self, grid: VoxelGrid, path_grid: VoxelGrid, link: Link, filled: CellKeys) -> "Layout":
        return Layout(self, grid, path_grid, link, filled)


class _Segment(NamedTuple):
    end: np.ndarray
    along: np.ndarray
    up: np.ndarray
    scale: float
    span: float
    placement: Placement


class Layout:
    """Lays chains of one link along paths."""

    def __init__(self, source: ChainLayout, grid: VoxelGrid, path_grid: VoxelGrid, link: Link, filled: CellKeys):
        self.source = source
        self.grid = grid
        self.path_grid = path_grid
        self.link = link
        self.filled = filled

    def grown(self, path: Path, seed: float, ladder: np.ndarray) -> Optional[Chain]:
        """Grows a chain from seed forward along the path, then backward."""
        _, ahead = self._run(path, seed, ladder, None, self.source.segments, backward=False)
        first = ahead[0]._replace(along=-ahead[0].along) if ahead else None
        start, behind = self._run(path.reversed(), path.length - seed, ladder, first,
                                  self.source.segments - len(ahead), backward=True)
        segments = behind[::-1] + ahead
        if not segments:
            return None
        joints = [segment.end for segment in behind[::-1]] + [start] + [segment.end for segment in ahead]
        return Chain(self.link, np.array(joints), np.array([segment.up for segment in segments]),
                     np.array([segment.scale for segment in segments]), [segment.placement for segment in segments])

    def fits(self, placement: Placement) -> bool:
        return self.source.fits(self.grid, placement, self.filled)

    def _run(self, path: Path, distance: float, ladder: np.ndarray, previous: Optional[_Segment], count: int, *,
             backward: bool) -> tuple[np.ndarray, list[_Segment]]:
        """Lays up to count segments in a row from distance along the path, after previous if there is one.
        Also returns where the row starts. A backward row walks the chain's path in reverse.
        """
        start = here = path.at(distance)[0]
        segments = []
        while len(segments) < count:
            segment = self._next(path, distance, here, ladder, previous, backward)
            if segment is None:
                break
            segments.append(segment)
            distance += segment.span
            here, previous = segment.end, segment
        return start, segments

    def _next(self, path: Path, distance: float, start: np.ndarray, ladder: np.ndarray, previous: Optional[_Segment],
              backward: bool) -> Optional[_Segment]:
        """The biggest segment that can follow previous from start, or None."""
        source, link = self.source, self.link
        for scale in ladder:
            if previous is not None and not (previous.scale / source.taper - 1e-9 <= scale
                                             <= previous.scale * source.taper + 1e-9):
                continue
            span = link.pose.length * scale * (1 - link.overlap)
            if distance + span > path.length + 1e-9:
                continue
            end = path.at(distance + span)[0]
            along = unit(end - start)
            if previous is not None and angle_between(along, previous.along) > link.max_bend:
                continue
            up = source.up_at(self.path_grid, path, distance, span, None if previous is None else previous.up)
            # Every segment faces the way the chain runs, so an item that isn't the same end for end doesn't flip.
            first, last = (end, start) if backward else (start, end)
            placement = link.placed(first, last, up, float(scale))
            if self.fits(placement) and source.has_room(self.path_grid, link, placement):
                return _Segment(end, along, up, scale, span, placement)
        return None


class MedialChains(ChainLayout, ChainSource):
    """Chains through the middle of long, thin parts. For cases when item fills the part from inside and shows on several sides."""

    type: Literal["medial_chains"] = "medial_chains"
    chains: PositiveInt = 16
    room: Annotated[float, Field(ge=1, allow_inf_nan=False)] = 2.5
    min_end_contact: Fraction = 0.5

    def allows(self, pose: Pose) -> bool:
        return pose.end_contact >= self.min_end_contact

    def propose_chains(self, task, placements, rng):
        grid, path_grid = self.voxel_grid(task.target), self.path_voxel_grid(task.target)
        filled = grid.item_cells.occupied_by_any(placements)
        flow = path_grid.flow
        points = path_grid.points_of(flow.medial_indices)
        points = points[~contains_sorted(filled, cell_keys(grid.indices_of(points)))]
        if not len(points):
            return []
        # Thin parts have few medial cells, so they get more weight, or they would rarely get chains.
        weights = 1.0 / np.maximum(flow.depth_at(points), 1.0)
        chosen = rng.choice(len(points), min(self.chains, len(points)), replace=False, p=weights / weights.sum())
        return self.grown_from(task, grid, points[chosen], filled)

    def grown_from(self, task: FittingTask, grid: VoxelGrid, points: np.ndarray, filled: CellKeys) -> list[Chain]:
        """Chains of every item along the medial paths through these points."""
        path_grid = self.path_voxel_grid(task.target)
        reach = self.segments * max(item.shape.length for item in task.catalog) * task.constraints.scale_bounds[1]
        chains = []
        for point in points:
            path, seed = medial_path(path_grid, point, reach)
            for item in task.catalog:
                chains.extend(self.laid(task, grid, path_grid, item, path, seed, filled, "middle"))
        return chains

    def up_at(self, grid, path, distance, span, previous):
        start, end = path.at([distance, distance + span])
        thin = grid.flow.thin_direction((start + end) / 2, unit(end - start))
        if thin is None:
            return np.array([0.0, 0.0, 1.0]) if previous is None else previous
        return thin if previous is None or np.dot(thin, previous) >= 0 else -thin

    def has_room(self, grid, link, placement):
        middle = placement.world_points(link.pose.middle)
        width = 2.0 * grid.flow.depth_at(middle[None])[0] * grid.pitch
        return width <= self.room * link.pose.width * placement.scale


class SurfaceChains(ChainLayout, SurfaceSettings, ChainSource):
    """Rows of items lying flat just inside the surface.
    Rows start at uncovered spots or next to placed items, follow the grain, and stop at sharp edges.
    """

    type: Literal["surface_chains"] = "surface_chains"
    chains: PositiveInt = 16
    beside: NonNegativeInt = 8
    edge: Annotated[float, Field(gt=0, le=180)] = 45.0
    skin_only: bool = True
    min_side_contact: Fraction = 0.4

    def allows(self, pose: Pose) -> bool:
        return pose.side_contact >= self.min_side_contact

    def propose_chains(self, task, placements, rng):
        grid, path_grid = self.voxel_grid(task.target), self.path_voxel_grid(task.target)
        filled = grid.item_cells.occupied_by_any(placements)
        uncovered = cell_indices(uncovered_surface_keys(grid, placements, self.tolerance_for(task.target),
                                                        skin_only=self.skin_only))
        starts = [(point, None) for point in grid.points_of(uncovered[sample_positions(rng, len(uncovered),
                                                                                       self.chains)])]
        for index in sample_positions(rng, len(placements), self.beside):
            starts.extend(self._beside(placements[index]))
        reach = self.segments * max(item.shape.length for item in task.catalog) * task.constraints.scale_bounds[1]
        chains = []
        for point, heading in starts:
            path, seed = surface_path(path_grid, point, heading, reach, self.edge)
            for item in task.catalog:
                chains.extend(self.laid(task, grid, path_grid, item, path, seed, filled, "outer"))
        return chains

    def _beside(self, placement: Placement) -> list[tuple[np.ndarray, np.ndarray]]:
        """Start points one item width to either side of a placement, heading along its long side."""
        shape = placement.item.shape
        axes = placement.rotation @ shape.axes
        middle = placement.world_points(shape.middle)
        width = shape.width * placement.scale * (1 - self.overlap)
        return [(middle + sign * width * axes[:, 1], axes[:, 0]) for sign in (-1.0, 1.0)]
