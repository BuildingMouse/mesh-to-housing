from dataclasses import dataclass

from ....geometry.cells import select_keys
from ..base import PenaltySession, VoxelLoss, VoxelLossConfig


@dataclass(frozen=True)
class OutsideVolumeConfig(VoxelLossConfig):
    def build(self):
        return OutsideVolumeLoss(self)


class OutsideVolumeLoss(VoxelLoss):
    """Construction volume outside the target divided by target volume."""

    def session(self, target):
        grid = self.grid(target)

        def outside_cells(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), lambda keys: ~grid.in_target(keys))

        return PenaltySession(outside_cells, reference=len(grid.keys))
