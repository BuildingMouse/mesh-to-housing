from typing import Literal

from ...geometry.settings import GridSettings, RoughnessSettings, SurfaceSettings
from ..base import LossConfig
from ..cell_sessions import CoverageSession, PenaltySession


class VoxelLossConfig(GridSettings, LossConfig):
    pass


class SurfaceToleranceConfig(SurfaceSettings, VoxelLossConfig):
    pass


class SurfaceDirectionConfig(VoxelLossConfig):
    direction: Literal["both", "to_target", "to_construction"] = "both"


class RoughnessConfig(RoughnessSettings, VoxelLossConfig):
    pass

