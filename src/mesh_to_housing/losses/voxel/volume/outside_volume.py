from typing import Literal

from ....geometry.cells import select_keys
from ...base import IncrementalLoss, implements
from ..base import PenaltySession, VoxelLossConfig


class OutsideVolumeConfig(VoxelLossConfig):
    type: Literal["outside_volume"] = "outside_volume"


@implements(OutsideVolumeConfig)
class OutsideVolumeLoss(IncrementalLoss):
    """Construction volume outside the target divided by target volume."""

    def session(self, target):
        grid = self.config.voxel_grid(target)

        def outside_cells(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), lambda keys: ~grid.in_target(keys))

        return PenaltySession(outside_cells, reference=len(grid.keys))
