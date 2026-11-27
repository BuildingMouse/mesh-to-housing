from typing import Literal

from ....geometry.cells import select_keys
from ...base import IncrementalLoss, implements
from ...cell_sessions import PenaltySession
from ..base import SurfaceToleranceConfig


class ExcessSurfaceConfig(SurfaceToleranceConfig):
    type: Literal["excess_surface"] = "excess_surface"


@implements(ExcessSurfaceConfig)
class ExcessSurfaceLoss(IncrementalLoss):
    def session(self, target):
        grid = self.config.voxel_grid(target)
        tolerance = self.config.tolerance_for(target)

        def standing_off(placements):
            return select_keys(grid.item_cells.skins_of_each(placements),
                               lambda keys: grid.outside_distance(keys) > tolerance)

        return PenaltySession(standing_off, reference=len(grid.surface))
