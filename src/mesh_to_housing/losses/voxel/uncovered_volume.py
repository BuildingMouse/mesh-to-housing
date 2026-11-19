from dataclasses import dataclass

from ...geometry.volume import occupied_cells
from .base import CoverageSession, VoxelLoss, VoxelLossConfig


@dataclass(frozen=True)
class UncoveredVolumeConfig(VoxelLossConfig):
    def build(self):
        return UncoveredVolumeLoss(self)


class UncoveredVolumeLoss(VoxelLoss):
    """Uncovered target volume divided by target volume."""

    def session(self, target):
        grid = self.grid(target)

        def covered_cells(placement):
            return occupied_cells(grid, placement) & grid.cells

        return CoverageSession(covered_cells, reference_count=len(grid.cells))
