from abc import abstractmethod
from typing import Literal

import numpy as np

from ....geometry.outer_surface import nearest_distances, outer_surfaces
from ...base import Loss, implements
from ..base import SurfaceToleranceConfig


class SurfacePrecisionConfig(SurfaceToleranceConfig):
    type: Literal["surface_precision"] = "surface_precision"


class SurfaceRecallConfig(SurfaceToleranceConfig):
    type: Literal["surface_recall"] = "surface_recall"


class SurfaceFScoreConfig(SurfaceToleranceConfig):
    type: Literal["surface_fscore"] = "surface_fscore"


class SurfaceScoreLoss(Loss):
    """One minus a score of the two surfaces at a distance tolerance."""

    def __call__(self, target, construction):
        grid = self.config.voxel_grid(target)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        tolerance = self.config.tolerance_for(target)
        precision = _share_within(construction_surface, target_surface, grid.pitch, tolerance)
        recall = _share_within(target_surface, construction_surface, grid.pitch, tolerance)
        return 1.0 - self.score(precision, recall)

    @abstractmethod
    def score(self, precision: float, recall: float) -> float:
        pass


@implements(SurfacePrecisionConfig)
class SurfacePrecisionLoss(SurfaceScoreLoss):
    """The share of the construction's outer surface farther than the tolerance from the target surface."""

    def score(self, precision, recall):
        return precision


@implements(SurfaceRecallConfig)
class SurfaceRecallLoss(SurfaceScoreLoss):
    """The share of the target surface farther than the tolerance from the construction's outer surface.
    Unlike uncovered surface, target surface buried deeper than the tolerance inside an item counts as missed.
    """

    def score(self, precision, recall):
        return recall


@implements(SurfaceFScoreConfig)
class SurfaceFScoreLoss(SurfaceScoreLoss):
    """One minus the harmonic mean of precision and recall."""

    def score(self, precision, recall):
        return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def _share_within(from_mask, to_mask, pitch, tolerance):
    if not from_mask.any() or not to_mask.any():
        return 0.0
    return float(np.mean(nearest_distances(from_mask, to_mask, pitch) <= tolerance))
