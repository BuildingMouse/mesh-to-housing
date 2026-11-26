from dataclasses import dataclass

import numpy as np
import trimesh

_AXIS_NAMES = ("long", "middle", "thin")


@dataclass(frozen=True, eq=False)
class OrientedBox:
    """How far an item reaches from its origin along three directions of its frame."""

    axes: np.ndarray
    low: np.ndarray
    high: np.ndarray

    @property
    def length(self) -> float:
        return float(self.high[0] - self.low[0])

    @property
    def width(self) -> float:
        return float(self.high[1] - self.low[1])

    @property
    def thickness(self) -> float:
        return float(self.high[2] - self.low[2])

    def point(self, coordinates: np.ndarray) -> np.ndarray:
        """The point in the item's frame with these coordinates along the three directions."""
        return self.axes @ np.asarray(coordinates, dtype=float)

    @property
    def middle(self) -> np.ndarray:
        return self.point((self.low + self.high) / 2)


@dataclass(frozen=True, eq=False)
class Pose(OrientedBox):
    """One way to lay an item along a chain: one of its own axes along the chain and one of its sides up. The end
    contact says how flush neighbors meet at the joints, and the side contact how flush the up side lies on a
    surface.
    """

    name: str
    end_contact: float
    side_contact: float

    @property
    def outer_middle(self) -> np.ndarray:
        """The middle of its up side."""
        middle = (self.low + self.high) / 2
        return self.point((middle[0], middle[1], self.high[2]))


@dataclass(frozen=True, eq=False)
class ItemShape(OrientedBox):
    """An item's own axes, from its longest side to its thinnest, taken from its tightest oriented box, with how
    much of that box it fills and the poses chains can lay it in.
    """

    samples: np.ndarray
    fill: float
    poses: tuple[Pose, ...]

    @classmethod
    def of(cls, mesh: trimesh.Trimesh, sample_count: int = 256, cells: int = 32) -> "ItemShape":
        to_box, _ = trimesh.bounds.oriented_bounds(mesh)
        directions = to_box[:3, :3].T
        reach = mesh.vertices @ directions
        sides = reach.max(axis=0) - reach.min(axis=0)
        # A stable sort keeps the mesh's own axis order between equal sides, so cuboids keep their faces.
        order = np.argsort(-np.round(sides, 9), kind="stable")
        axes = directions[:, order]
        if np.linalg.det(axes) < 0:
            axes[:, 2] = -axes[:, 2]
        sampled, _ = trimesh.sample.sample_surface_even(mesh, sample_count, seed=0)
        # The hull's corners are the item's extremes, and there are few of them even on a dense mesh.
        samples = np.vstack((mesh.convex_hull.vertices, sampled))
        solid = _solid_along(mesh, axes, cells)
        poses = tuple(_pose(samples, axes, solid, along, up, sign)
                      for along in range(3) for up in range(3) if up != along for sign in (1.0, -1.0))
        reach = mesh.vertices @ axes
        return cls(axes, reach.min(axis=0), reach.max(axis=0), samples, float(solid.mean()), poses)

    def pose(self, name: str) -> Pose:
        return next(pose for pose in self.poses if pose.name == name)


def _solid_along(mesh: trimesh.Trimesh, axes: np.ndarray, cells: int) -> np.ndarray:
    """The item's filled cells on a grid that runs along its own axes, with as many cells along each axis."""
    from ..geometry.voxel_grid import VoxelGridConfig
    from ..geometry.voxelization import voxelize

    turned = mesh.copy()
    turned.apply_transform(np.vstack((np.column_stack((axes.T, np.zeros(3))), (0, 0, 0, 1))))
    low, high = turned.bounds
    # Stretched into a unit cube, so a thin side gets as many cells as a long one.
    turned.apply_translation(-low)
    turned.vertices = turned.vertices / (high - low)
    return voxelize(turned, VoxelGridConfig(voxel_pitch=1.0 / cells, target_samples=1)).solid_mask


def _pose(samples: np.ndarray, axes: np.ndarray, solid: np.ndarray, along: int, up: int, sign: float) -> Pose:
    up_direction = axes[:, up] * sign
    pose_axes = np.column_stack((axes[:, along], np.cross(up_direction, axes[:, along]), up_direction))
    reach = samples @ pose_axes
    name = f"{_AXIS_NAMES[along]} along, {'+' if sign > 0 else '-'}{_AXIS_NAMES[up]} up"
    ends = (_contact(solid, along, 1.0) + _contact(solid, along, -1.0)) / 2
    return Pose(pose_axes, reach.min(axis=0), reach.max(axis=0), name, ends, _contact(solid, up, sign))


def _contact(solid: np.ndarray, axis: int, sign: float, depth_share: float = 0.06) -> float:
    """The share of one side of the item's box that the item reaches, within a small depth of it."""
    count = solid.shape[axis]
    depth = max(1, round(depth_share * count))
    layers = range(count - depth, count) if sign > 0 else range(depth)
    return float(np.take(solid, list(layers), axis=axis).any(axis=axis).mean())
