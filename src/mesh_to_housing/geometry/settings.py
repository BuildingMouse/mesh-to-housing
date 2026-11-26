from typing import Optional

from pydantic import Field

from ..utils.config import Config
from ..utils.values import NonNegativeFloat, PositiveFloat
from .voxel_grid import VoxelGrid, VoxelGridConfig


class GridSettings(Config):
    grid: VoxelGridConfig = Field(default_factory=VoxelGridConfig)

    def voxel_grid(self, target):
        return VoxelGrid.from_mesh(target, self.grid)


class PathSettings(GridSettings):
    path_grid: Optional[VoxelGridConfig] = None

    def path_voxel_grid(self, target):
        return VoxelGrid.from_mesh(target, self.grid if self.path_grid is None else self.path_grid)


class SurfaceSettings(GridSettings):
    surface_tolerance: Optional[NonNegativeFloat] = None

    def tolerance_for(self, target):
        return float(target.extents.max() / 96 if self.surface_tolerance is None else self.surface_tolerance)


class RoughnessSettings(GridSettings):
    """Roughness is measured within roughness_radius of each surface cell, two cells unless set."""

    roughness_radius: Optional[PositiveFloat] = None

    def roughness_radius_for(self, grid: VoxelGrid) -> float:
        return 2 * grid.pitch if self.roughness_radius is None else self.roughness_radius


class ThinnessSettings(GridSettings):
    """A part counts as thin when it is narrower than twice thinness_radius, four cells unless set."""

    thinness_radius: Optional[PositiveFloat] = None

    def thinness_radius_for(self, grid: VoxelGrid) -> float:
        return 4 * grid.pitch if self.thinness_radius is None else self.thinness_radius
