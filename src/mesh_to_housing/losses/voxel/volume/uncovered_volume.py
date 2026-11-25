from typing import Literal

from ....geometry.cells import select_keys
from ...base import IncrementalLoss, implements
from ..base import CoverageSession, VoxelLossConfig


class UncoveredVolumeConfig(VoxelLossConfig):
    type: Literal["uncovered_volume"] = "uncovered_volume"


@implements(UncoveredVolumeConfig)
class UncoveredVolumeLoss(IncrementalLoss):
    """Uncovered target volume divided by target volume."""

    def session(self, target):
        grid = self.config.voxel_grid(target)

        def covered_cells(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), grid.in_target)

        return CoverageSession(covered_cells, reference=len(grid.keys))
