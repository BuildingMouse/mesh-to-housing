from dataclasses import dataclass, field

import numpy as np

from ..construction import Construction
from ..geometry.config import GeometryConfig
from ..geometry.volume import VoxelGrid
from ..placement import Placement
from ..validation import positive_integer
from .fitting_algorithm import FittingAlgorithm

# Keeps rounding noise in a sum of loss terms from counting as an improvement.
_MIN_GAIN = 1e-12


@dataclass
class RandomPlacementGreedy(FittingAlgorithm):
    """Sample a fixed pool, then keep adding its best placement until the budget is used or nothing lowers the loss."""

    geometry: GeometryConfig = field(default_factory=GeometryConfig)
    candidate_centers: int = 256
    scale_count: int = 5
    orientation_count: int = 8

    def __post_init__(self):
        for name in ("candidate_centers", "scale_count", "orientation_count"):
            positive_integer(getattr(self, name), name)

    def fit(self, task, loss, *, rng):
        grid = VoxelGrid.from_mesh(task.target, pitch=self.geometry.voxel_pitch, closing=self.geometry.closing)
        pool = list(_sampled_placements(
            task, grid, rng=rng, candidate_centers=self.candidate_centers,
            scale_count=self.scale_count, orientation_count=self.orientation_count,
        ))
        session = loss.session(task.target)
        placements = []
        while len(placements) < task.max_items and pool:
            gains = [session.gain(placement) for placement in pool]
            best = int(np.argmax(gains))
            if gains[best] <= _MIN_GAIN:
                break
            placements.append(pool.pop(best))
            session.add(placements[-1])
        return Construction(tuple(placements))


def _sample_rotations(count, rng):
    from scipy.spatial.transform import Rotation

    rotations = [np.eye(3), Rotation.from_euler("x", 90, degrees=True).as_matrix(),
                 Rotation.from_euler("y", 90, degrees=True).as_matrix()][:count]
    if count > 3:
        rotations.extend(Rotation.random(count - 3, random_state=rng).as_matrix())
    return rotations


def _sampled_placements(task, grid, *, rng, candidate_centers, scale_count, orientation_count):
    indices = grid.indices[rng.choice(len(grid.indices), min(candidate_centers, len(grid.indices)), replace=False)]
    centers = grid.origin + indices * grid.pitch
    scales = task.constraints.sample_scales(scale_count)
    rotations = _sample_rotations(orientation_count, rng)
    for center in centers:
        for rotation in rotations:
            for scale in scales:
                for item in task.catalog:
                    yield Placement(item, center, rotation, scale)
