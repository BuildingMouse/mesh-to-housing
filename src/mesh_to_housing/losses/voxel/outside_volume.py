from dataclasses import dataclass

from ...geometry.volume import occupied_cells
from .base import PenaltySession, VoxelLoss, VoxelLossConfig


@dataclass(frozen=True)
class OutsideVolumeConfig(VoxelLossConfig):
    def build(self):
        return OutsideVolumeLoss(self)


class OutsideVolumeLoss(VoxelLoss):
    """Construction volume outside the target divided by target volume."""

    def session(self, target):
        grid = self.grid(target)

        def outside_cells(placement):
            return occupied_cells(grid, placement) - grid.cells

        return PenaltySession(outside_cells, reference_count=len(grid.cells))
