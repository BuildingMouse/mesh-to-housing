import numpy as np

from ..geometry.features import normal_variation


def normal_weighted(mesh, count, *, candidates, important_points, rng, strength=8.0):
    if not np.isfinite(strength) or strength < 0:
        raise ValueError("strength must be finite and nonnegative")
    scores = normal_variation(mesh)[candidates] / np.pi
    # Scale before normalizing to keep even large strengths numerically safe.
    weights = 1 / (1 + strength) + (strength / (1 + strength)) * scores
    return rng.choice(candidates, size=count, replace=False, p=weights / weights.sum())
