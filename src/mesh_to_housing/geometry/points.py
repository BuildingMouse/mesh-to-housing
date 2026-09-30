import numpy as np


def unique_points(points) -> np.ndarray:
    if points is None:
        return np.empty((0, 3), dtype=float)
    points = np.asarray(points, dtype=float)
    if points.shape == (0,):
        points = points.reshape(0, 3)
    if points.ndim != 2 or points.shape[1] != 3 or not np.isfinite(points).all():
        raise ValueError("important_points must be a finite (N, 3) array")
    _, first = np.unique(points, axis=0, return_index=True)
    return points[np.sort(first)].copy()
