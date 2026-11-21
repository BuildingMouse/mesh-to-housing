from dataclasses import dataclass

from ...geometry.cells import select_keys
from .base import CoverageSession, VoxelLoss, VoxelLossConfig


@dataclass(frozen=True)
class UncoveredVolumeConfig(VoxelLossConfig):
    def build(self):
        return UncoveredVolumeLoss(self)


class UncoveredVolumeLoss(VoxelLoss):
    """Uncovered target volume divided by target volume."""

    def session(self, target):
        grid = self.grid(target)

        def covered_cells(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), grid.in_target)

        return CoverageSession(covered_cells, reference=len(grid.keys))
