from abc import abstractmethod
from dataclasses import dataclass

import numpy as np

from ...geometry.volume import VoxelGrid, nearest_distances, outer_surfaces
from ..base import Loss
from .base import SurfaceToleranceConfig


@dataclass(frozen=True)
class SurfacePrecisionConfig(SurfaceToleranceConfig):
    def build(self):
        return SurfacePrecisionLoss(self)


@dataclass(frozen=True)
class SurfaceRecallConfig(SurfaceToleranceConfig):
    def build(self):
        return SurfaceRecallLoss(self)


@dataclass(frozen=True)
class SurfaceFScoreConfig(SurfaceToleranceConfig):
    def build(self):
        return SurfaceFScoreLoss(self)


class SurfaceScoreLoss(Loss):
    """One minus a score at a distance tolerance"""

    def __call__(self, target, construction):
        grid = VoxelGrid.from_mesh(target, self.config.grid)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        tolerance = self.config.tolerance_for(target)
        precision = _share_within(construction_surface, target_surface, grid.pitch, tolerance)
        recall = _share_within(target_surface, construction_surface, grid.pitch, tolerance)
        return 1.0 - self.score(precision, recall)

    @abstractmethod
    def score(self, precision, recall):
        pass


class SurfacePrecisionLoss(SurfaceScoreLoss):
    """The share of the construction's outer surface farther than the tolerance from the target surface."""

    def score(self, precision, recall):
        return precision


class SurfaceRecallLoss(SurfaceScoreLoss):
    """The share of the target surface farther than the tolerance from the construction's outer surface.
    Unlike uncovered surface, target surface buried deeper than the tolerance inside an item counts as missed.
    """

    def score(self, precision, recall):
        return recall


class SurfaceFScoreLoss(SurfaceScoreLoss):

    def score(self, precision, recall):
        return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def _share_within(from_mask, to_mask, pitch, tolerance):
    if not from_mask.any() or not to_mask.any():
        return 0.0
    return float(np.mean(nearest_distances(from_mask, to_mask, pitch) <= tolerance))
