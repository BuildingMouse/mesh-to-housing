from typing import Literal

from ....geometry.cells import select_keys
from ...base import implements
from ..base import CoverageSession, VoxelLoss, VoxelLossConfig


class UncoveredVolumeConfig(VoxelLossConfig):
    type: Literal["uncovered_volume"] = "uncovered_volume"


@implements(UncoveredVolumeConfig)
class UncoveredVolumeLoss(VoxelLoss):
    """Uncovered target volume divided by target volume."""

    def session(self, target):
        grid = self.grid(target)

        def covered_cells(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), grid.in_target)

        return CoverageSession(covered_cells, reference=len(grid.keys))
