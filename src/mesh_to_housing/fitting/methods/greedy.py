import numpy as np

from ..result import FittingResult


def greedy(fitter, count, shape, *, rng, candidate_centers=256, scale_count=5,
           orientation_count=8, outside_weight=1.0):
    """Greedy volume coverage using sampled rotations and uniform scales."""
    from scipy.spatial.transform import Rotation

    assert orientation_count >= 1
    volume = fitter.volume
    points = volume.points
    centers = points[rng.choice(len(points), min(candidate_centers, len(points)), replace=False)]
    scales = np.unique(np.geomspace(*shape.scale_bounds, num=scale_count))[::-1]
    rotations = [np.eye(3), Rotation.from_euler("x", 90, degrees=True).as_matrix(),
                 Rotation.from_euler("y", 90, degrees=True).as_matrix()][:orientation_count]
    # we start with three preset rotations, anything beyond those is random.
    if orientation_count > 3:
        rotations.extend(Rotation.random(orientation_count - 3, random_state=rng).as_matrix())
    candidates = []
    for center in centers:
        for rotation in rotations:
            for scale in scales:
                cells = volume.placed_cells(shape, center, rotation, scale)
                inside = cells & volume.cells
                if inside:
                    candidates.append((center, rotation, scale, inside, cells - volume.cells))
    if len(candidates) < count:
        raise ValueError("Too few resolved candidates for n_items; increase candidate_centers or reduce volume_pitch")

    covered, outside, selected = set(), set(), []
    for _ in range(count):
        best, best_score = 0, (-np.inf,)
        for index, (_, _, _, inside, spill) in enumerate(candidates):
            gain, cost = len(inside - covered), len(spill - outside)
            score = (gain - outside_weight * cost, gain, -cost)
            if score > best_score:
                best, best_score = index, score
        center, rotation, scale, inside, spill = candidates.pop(best)
        selected.append((center, rotation, scale))
        covered.update(inside)
        outside.update(spill)
    centers, rotations, scales = zip(*selected)
    return FittingResult(shape, centers, rotations, scales)
