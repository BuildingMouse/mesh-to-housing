from typing import Literal

import numpy as np

from ....geometry.coverage import covered_surface_keys
from ....geometry.settings import RoughnessSettings, ThinnessSettings
from ....utils.values import NonNegativeFloat
from ...base import IncrementalLoss, implements
from ...cell_sessions import CoverageSession
from ..base import SurfaceToleranceConfig


class UncoveredSurfaceConfig(RoughnessSettings, ThinnessSettings, SurfaceToleranceConfig):
    type: Literal["uncovered_surface"] = "uncovered_surface"
    skin_only: bool = False
    roughness_weight: NonNegativeFloat = 0.0
    thinness_weight: NonNegativeFloat = 0.0


@implements(UncoveredSurfaceConfig)
class UncoveredSurfaceLoss(IncrementalLoss):
    """The share of the target surface that no item covers within the surface tolerance.

    Each target surface cell weighs 1 + roughness_weight * its roughness + thinness_weight * its thinness. Roughness
    makes claws, ears and edges count for more than a smooth face of the same area; thinness does the same for legs,
    tails and wings, which are easy to lose because they have little surface.
    """

    def session(self, target):
        grid = self.config.voxel_grid(target)
        tolerance = self.config.tolerance_for(target)

        def covered_surface(placements):
            return covered_surface_keys(grid, placements, tolerance, skin_only=self.config.skin_only)

        weights = self._weights(grid)
        if weights is None:
            return CoverageSession(covered_surface, reference=len(grid.surface))

        def weights_of(keys):
            return weights[grid.surface.index_of(keys)]

        return CoverageSession(covered_surface, reference=float(weights.sum()), weights=weights_of)

    def _weights(self, grid):
        config = self.config
        if config.roughness_weight == 0 and config.thinness_weight == 0:
            return None
        weights = np.ones(len(grid.surface))
        if config.roughness_weight:
            weights += config.roughness_weight * grid.surface.roughness(config.roughness_radius_for(grid))
        if config.thinness_weight:
            weights += config.thinness_weight * grid.surface.thinness(config.thinness_radius_for(grid))
        return weights
