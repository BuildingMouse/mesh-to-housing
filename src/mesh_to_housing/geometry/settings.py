from typing import Optional

from pydantic import Field

from ..utils.config import Config
from ..utils.values import NonNegativeFloat
from .voxel_grid import VoxelGrid, VoxelGridConfig


class GridSettings(Config):
    grid: VoxelGridConfig = Field(default_factory=VoxelGridConfig)

    def voxel_grid(self, target):
        return VoxelGrid.from_mesh(target, self.grid)


class SurfaceSettings(GridSettings):
    surface_tolerance: Optional[NonNegativeFloat] = None

    def tolerance_for(self, target):
        return float(target.extents.max() / 96 if self.surface_tolerance is None else self.surface_tolerance)
