from typing import Literal

import numpy as np

from ....geometry.outer_surface import nearest_distances, outer_surfaces
from ...base import Loss, implements
from ..base import SurfaceDirectionConfig, SurfaceToleranceConfig


class SurfaceFScoreConfig(SurfaceToleranceConfig, SurfaceDirectionConfig):
    type: Literal["surface_fscore"] = "surface_fscore"


@implements(SurfaceFScoreConfig)
class SurfaceFScoreLoss(Loss):
    """One minus the F-score of the outer surfaces of the target and the construction, at the surface tolerance.

    Precision is the share of the construction's outer surface within the tolerance of the target's, and recall is
    the share of the target's within the tolerance of the construction's. With direction to_target the loss uses
    the precision alone, and with to_construction the recall alone.
    """

    def __call__(self, target, construction):
        grid = self.config.voxel_grid(target)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        tolerance = self.config.tolerance_for(target)
        precision = _share_within(construction_surface, target_surface, grid.pitch, tolerance)
        recall = _share_within(target_surface, construction_surface, grid.pitch, tolerance)
        score = {
            "to_target": precision,
            "to_construction": recall,
            "both": 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall),
        }[self.config.direction]
        return 1.0 - score


def _share_within(from_mask, to_mask, pitch, tolerance):
    if not from_mask.any() or not to_mask.any():
        return 0.0
    return float(np.mean(nearest_distances(from_mask, to_mask, pitch) <= tolerance))
