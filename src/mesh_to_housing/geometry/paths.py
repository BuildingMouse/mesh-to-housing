"""Lines that chains are laid along, through the middle of the target's parts or over its surface."""
from typing import Optional

import numpy as np

from .cells import cell_keys
from .rotations import angle_between, side_and_up, unit


class Path:
    """A line through a series of points. A place on it is given by its distance from the first point."""

    def __init__(self, points: np.ndarray, normals: Optional[np.ndarray] = None):
        self.points = np.asarray(points, dtype=float).reshape(-1, 3)
        self.normals = normals
        steps = np.linalg.norm(np.diff(self.points, axis=0), axis=1)
        self.starts = np.concatenate(([0.0], np.cumsum(steps)))

    @property
    def length(self) -> float:
        return float(self.starts[-1])

    def at(self, distances) -> np.ndarray:
        """The points at these distances along the path."""
        distances = np.atleast_1d(np.asarray(distances, dtype=float))
        if len(self.points) == 1:
            return np.repeat(self.points, len(distances), axis=0)
        segment = np.clip(np.searchsorted(self.starts, distances, side="right") - 1, 0, len(self.points) - 2)
        length = np.maximum(self.starts[segment + 1] - self.starts[segment], 1e-12)
        share = (distances - self.starts[segment]) / length
        return self.points[segment] + share[:, None] * (self.points[segment + 1] - self.points[segment])

    def reversed(self) -> "Path":
        """The same path walked from its other end."""
        return Path(self.points[::-1], None if self.normals is None else self.normals[::-1])

    def normal_at(self, distance: float) -> np.ndarray:
        """The surface normal stored with the nearest point, for paths traced over the surface."""
        return self.normals[int(np.argmin(np.abs(self.starts - distance)))]


def medial_path(grid: "VoxelGrid", point: np.ndarray, reach: float) -> tuple[Path, float]:
    flow = grid.flow
    heading = flow.direction_at(point[None])[0]
    steps = int(np.ceil(reach / grid.pitch))

    def walk(heading):
        points, here = [point], point
        for _ in range(steps):
            turned = flow.direction_at(here[None])[0]
            heading = turned if np.dot(turned, heading) >= 0 else -turned
            ahead = here + heading * grid.pitch
            uphill = flow.uphill_at(ahead[None])[0]
            uphill -= np.dot(uphill, heading) * heading
            ahead = ahead + uphill * min(1.0, 0.5 / max(float(np.linalg.norm(uphill)), 1e-12)) * grid.pitch
            if flow.depth_at(ahead[None])[0] < 0.5:
                ahead = _back_inside(grid, here, ahead, heading)
            if ahead is None or _closes(points, ahead, grid.pitch):
                break
            points.append(ahead)
            here = ahead
        return points

    back = walk(-heading)
    path = Path(_smoothed(np.array(back[::-1] + walk(heading)[1:])))
    return path, float(path.starts[len(back) - 1])


def surface_path(grid: "VoxelGrid", point: np.ndarray, heading: Optional[np.ndarray], reach: float,
                 edge: float) -> tuple[Path, float]:
    start, normal = on_surface(grid, point)
    if heading is None:
        grain, has_grain = grid.surface.grain_at(start[None], normal[None])
        heading = grain[0] if has_grain[0] else grid.flow.direction_at(start[None])[0]
    steps = int(np.ceil(reach / grid.pitch))

    def walk(heading):
        points, normals = [start], [normal]
        here, toward, roll = start, _across(heading, normal), 0.0
        for _ in range(steps):
            ahead, facing = on_surface(grid, here + toward * grid.pitch)
            # A corner is spread over a few cells, so the normal is compared with the one a few steps back.
            if angle_between(facing, normals[max(len(normals) - 3, 0)]) > edge:
                break
            roll += _roll(normals[-1], facing, toward)
            if abs(roll) > edge:
                break
            if _closes(points, ahead, grid.pitch):
                break
            toward = _across(toward, facing)
            grain, has_grain = grid.surface.grain_at(ahead[None], facing[None])
            along = float(np.dot(grain[0], toward))
            if has_grain[0] and abs(along) >= np.sqrt(0.5):
                toward = _across(toward + grain[0] * np.sign(along), facing)
            points.append(ahead)
            normals.append(facing)
            here = ahead
        return points

    back = walk(-heading)
    ahead = walk(heading)
    smoothed = _smoothed(np.array(back[::-1] + ahead[1:]))
    points, normals = zip(*(on_surface(grid, along) for along in smoothed))
    path = Path(np.array(points), np.array(normals))
    return path, float(path.starts[len(back) - 1])


def on_surface(grid: "VoxelGrid", point: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    surface = grid.surface
    distances, nearest = surface.tree.query(point, k=24)
    weights = np.exp(-0.5 * (distances / grid.pitch) ** 2)
    normal = unit(weights @ surface.normals[nearest])
    level = weights @ surface.tree.data[nearest] / weights.sum() + normal * grid.pitch / 4
    return point - normal * np.dot(point - level, normal), normal


def _back_inside(grid: "VoxelGrid", here: np.ndarray, ahead: np.ndarray,
                 heading: np.ndarray) -> Optional[np.ndarray]:
    cells = grid.indices_of(here) + np.indices((3, 3, 3)).reshape(3, -1).T - 1
    cells = cells[grid.in_target(cell_keys(cells))]
    points = grid.points_of(cells)
    forward = (points - here) @ heading > 0.5 * grid.pitch
    if not forward.any():
        return None
    points = points[forward]
    return points[np.argmin(np.linalg.norm(points - ahead, axis=1))]


def _smoothed(points: np.ndarray, cells: float = 2.0) -> np.ndarray:
    from scipy.ndimage import gaussian_filter1d

    if len(points) < 3:
        return points
    smooth = gaussian_filter1d(points, cells, axis=0, mode="nearest")
    smooth[[0, -1]] = points[[0, -1]]
    return smooth


def _across(direction: np.ndarray, normal: np.ndarray) -> np.ndarray:
    return side_and_up(normal, direction)[1]


def _roll(before: np.ndarray, after: np.ndarray, heading: np.ndarray) -> float:
    first, second = (normal - np.dot(normal, heading) * heading for normal in (before, after))
    return float(np.degrees(np.arctan2(np.dot(np.cross(first, second), heading), np.dot(first, second))))


def _closes(points: list, point: np.ndarray, pitch: float) -> bool:
    return len(points) > 4 and float(np.linalg.norm(point - points[0])) < pitch
