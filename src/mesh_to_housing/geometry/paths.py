"""Lines that chains are laid along."""
from typing import Optional

import numpy as np


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
