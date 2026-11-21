from dataclasses import dataclass

from ....geometry.coverage import covered_surface_cells
from ...coverage import CoverageSession
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

        def covered_surface(placement):
            return covered_surface_cells(grid, placement, tolerance, skin_only=self.config.skin_only)

        return CoverageSession(covered_surface, reference_count=len(grid.surface))
