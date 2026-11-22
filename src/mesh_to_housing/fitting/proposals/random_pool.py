from typing import Literal

from pydantic import Field

from ...utils.config import Config
from ...utils.values import PositiveInt
from ...geometry.rotations import sample_rotations
from ...geometry.voxel_grid import VoxelGrid, VoxelGridConfig
from ...placement import Placement
from .base import Proposals, sample_positions


class RandomPool(Config, Proposals):
    """Candidates at random target cells, each with every orientation, scale and item."""

    type: Literal["random_pool"] = "random_pool"
    grid: VoxelGridConfig = Field(default_factory=VoxelGridConfig)
    centers: PositiveInt = 256
    orientations: PositiveInt = 8
    scales: PositiveInt = 5

    def propose(self, task, placements, rng):
        grid = VoxelGrid.from_mesh(task.target, self.grid)
        points = grid.points_of(grid.indices[sample_positions(rng, len(grid.indices), self.centers)])
        scales = task.constraints.sample_scales(self.scales)
        rotations = sample_rotations(self.orientations, rng)
        return [Placement(item, point, rotation, scale)
                for point in points for rotation in rotations for scale in scales for item in task.catalog]
