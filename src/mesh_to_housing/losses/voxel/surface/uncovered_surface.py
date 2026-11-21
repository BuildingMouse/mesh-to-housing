from dataclasses import dataclass

from ....geometry.coverage import covered_surface_keys
from ...cell_sessions import CoverageSession
from ..base import SurfaceToleranceConfig, VoxelLoss


@dataclass(frozen=True)
class UncoveredSurfaceConfig(SurfaceToleranceConfig):
    skin_only: bool = False

    def build(self):
        return UncoveredSurfaceLoss(self)


class UncoveredSurfaceLoss(VoxelLoss):
    def session(self, target):
        grid = self.grid(target)
        tolerance = self.config.tolerance_for(target)

        def covered_surface(placements):
            return covered_surface_keys(grid, placements, tolerance, skin_only=self.config.skin_only)

        return CoverageSession(covered_surface, reference=len(grid.surface))
