from dataclasses import dataclass

from ....geometry.cells import select_keys
from ...cell_sessions import PenaltySession
from ..base import SurfaceToleranceConfig, VoxelLoss


@dataclass(frozen=True)
class ExcessSurfaceConfig(SurfaceToleranceConfig):
    def build(self):
        return ExcessSurfaceLoss(self)


class ExcessSurfaceLoss(VoxelLoss):
    def session(self, target):
        grid = self.grid(target)
        tolerance = self.config.tolerance_for(target)

        def standing_off(placements):
            return select_keys(grid.item_cells.skins_of_each(placements),
                               lambda keys: grid.outside_distance(keys) > tolerance)

        return PenaltySession(standing_off, reference=len(grid.surface))
