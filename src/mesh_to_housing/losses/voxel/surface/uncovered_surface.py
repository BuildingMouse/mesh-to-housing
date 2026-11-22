from typing import Literal

from ....geometry.coverage import covered_surface_keys
from ...base import implements
from ...cell_sessions import CoverageSession
from ..base import SurfaceToleranceConfig, VoxelLoss


class UncoveredSurfaceConfig(SurfaceToleranceConfig):
    type: Literal["uncovered_surface"] = "uncovered_surface"
    skin_only: bool = False


@implements(UncoveredSurfaceConfig)
class UncoveredSurfaceLoss(VoxelLoss):
    def session(self, target):
        grid = self.grid(target)
        tolerance = self.config.tolerance_for(target)

        def covered_surface(placements):
            return covered_surface_keys(grid, placements, tolerance, skin_only=self.config.skin_only)

        return CoverageSession(covered_surface, reference=len(grid.surface))
