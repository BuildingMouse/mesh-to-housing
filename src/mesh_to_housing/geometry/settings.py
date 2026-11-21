from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from .config import VoxelGridConfig
from .volume import VoxelGrid


@dataclass(frozen=True)
class GridSettings:
    grid: VoxelGridConfig = field(default_factory=VoxelGridConfig)

    def voxel_grid(self, target):
        return VoxelGrid.from_mesh(target, self.grid)


@dataclass(frozen=True)
class SurfaceSettings(GridSettings):
    surface_tolerance: Optional[float] = None

    def __post_init__(self):
        if self.surface_tolerance is not None and (
                not np.isfinite(self.surface_tolerance) or self.surface_tolerance < 0):
            raise ValueError("surface_tolerance must be finite and nonnegative")

    def tolerance_for(self, target):
        return float(target.extents.max() / 96 if self.surface_tolerance is None else self.surface_tolerance)
