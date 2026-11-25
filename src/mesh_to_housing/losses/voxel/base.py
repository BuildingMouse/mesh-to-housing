from typing import Literal

from ...geometry.settings import GridSettings, RoughnessSettings, SurfaceSettings
from ...geometry.voxel_grid import VoxelGrid
from ..base import IncrementalLoss, LossConfig
from ..cell_sessions import CoverageSession, PenaltySession


class VoxelLossConfig(GridSettings, LossConfig):
    pass


class SurfaceToleranceConfig(SurfaceSettings, VoxelLossConfig):
    pass


class SurfaceDirectionConfig(VoxelLossConfig):
    direction: Literal["both", "to_target", "to_construction"] = "both"


class RoughnessConfig(RoughnessSettings, VoxelLossConfig):
    pass


class VoxelLoss(IncrementalLoss):
    def grid(self, target):
        return VoxelGrid.from_mesh(target, self.config.grid)
