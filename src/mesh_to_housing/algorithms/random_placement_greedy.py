from dataclasses import dataclass, field

from ..fitting.algorithm import FittingAlgorithm
from ..fitting.algorithms.greedy import Greedy
from ..fitting.proposals import RandomPool
from ..geometry.config import VoxelGridConfig
from ..validation import positive_integer


@dataclass
class RandomPlacementGreedy(FittingAlgorithm):
    grid: VoxelGridConfig = field(default_factory=VoxelGridConfig)
    candidate_centers: int = 256
    scale_count: int = 5
    orientation_count: int = 8

    def __post_init__(self):
        for name in ("candidate_centers", "scale_count", "orientation_count"):
            positive_integer(getattr(self, name), name)

    def fit(self, task, loss, *, rng):
        pool = RandomPool(grid=self.grid, centers=self.candidate_centers,
                          orientations=self.orientation_count, scales=self.scale_count)
        return Greedy(pool=pool).fit(task, loss, rng=rng)
