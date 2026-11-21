from dataclasses import dataclass, field

from ...geometry.config import VoxelGridConfig
from ...geometry.volume import VoxelGrid
from ..base import IncrementalLoss, LossConfig
from ..coverage import CoverageSession, PenaltySession


@dataclass(frozen=True)
class VoxelLossConfig(LossConfig):
    grid: VoxelGridConfig = field(default_factory=VoxelGridConfig)


class VoxelLoss(IncrementalLoss):
    def grid(self, target):
        return VoxelGrid.from_mesh(target, self.config.grid)
