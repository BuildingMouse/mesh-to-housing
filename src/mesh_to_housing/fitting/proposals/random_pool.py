from dataclasses import dataclass, field

from ...geometry.config import VoxelGridConfig
from ...geometry.rotations import sample_rotations
from ...geometry.volume import VoxelGrid
from ...placement import Placement
from ...validation import positive_integer
from .base import Proposals


@dataclass(frozen=True)
class RandomPool(Proposals):
    grid: VoxelGridConfig = field(default_factory=VoxelGridConfig)
    centers: int = 256
    orientations: int = 8
    scales: int = 5

    def __post_init__(self):
        for name in ("centers", "orientations", "scales"):
            positive_integer(getattr(self, name), name)

    def propose(self, task, placements, rng):
        grid = VoxelGrid.from_mesh(task.target, self.grid)
        indices = grid.indices[rng.choice(len(grid.indices), min(self.centers, len(grid.indices)), replace=False)]
        points = grid.origin + indices * grid.pitch
        scales = task.constraints.sample_scales(self.scales)
        rotations = sample_rotations(self.orientations, rng)
        return [Placement(item, point, rotation, scale)
                for point in points for rotation in rotations for scale in scales for item in task.catalog]
