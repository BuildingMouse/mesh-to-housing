from dataclasses import dataclass

from ....geometry.coverage import excess_surface_cells
from ...coverage import PenaltySession
from ..base import SurfaceToleranceConfig, VoxelLoss


@dataclass(frozen=True)
class ExcessSurfaceConfig(SurfaceToleranceConfig):
    def build(self):
        return ExcessSurfaceLoss(self)


class ExcessSurfaceLoss(VoxelLoss):
    def session(self, target):
        grid = self.grid(target)
        tolerance = self.config.tolerance_for(target)

        def standing_off(placement):
            return excess_surface_cells(grid, placement, tolerance)

        return PenaltySession(standing_off, reference_count=len(grid.surface))
