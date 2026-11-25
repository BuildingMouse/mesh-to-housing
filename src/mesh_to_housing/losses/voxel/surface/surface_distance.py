from abc import abstractmethod
from typing import Literal

import numpy as np

from ....geometry.outer_surface import nearest_distances, outer_surfaces
from ...base import Loss, implements
from ..base import SurfaceDirectionConfig


class ChamferDistanceConfig(SurfaceDirectionConfig):
    type: Literal["chamfer_distance"] = "chamfer_distance"


class HausdorffDistanceConfig(SurfaceDirectionConfig):
    type: Literal["hausdorff_distance"] = "hausdorff_distance"


class SurfaceDistanceLoss(Loss):
    """A summary of the distances between the outer surfaces of the target and the construction.
    Distances are divided by the target's longest side, so they keep their meaning at any target size.
    """

    def __call__(self, target, construction):
        grid = self.config.voxel_grid(target)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        if not construction_surface.any():
            # A finite value lets a greedy fit rank its first item. Infinity would make every first gain equal.
            return 1.0
        to_target = self.reduce(nearest_distances(construction_surface, target_surface, grid.pitch))
        to_construction = self.reduce(nearest_distances(target_surface, construction_surface, grid.pitch))
        value = {
            "to_target": to_target,
            "to_construction": to_construction,
            "both": self.reduce([to_target, to_construction]),
        }[self.config.direction]
        return float(value / target.extents.max())

    @abstractmethod
    def reduce(self, distances: np.ndarray) -> float:
        pass


@implements(ChamferDistanceConfig)
class ChamferDistanceLoss(SurfaceDistanceLoss):
    """The mean distance from one surface to the other."""

    def reduce(self, distances):
        return np.mean(distances)


@implements(HausdorffDistanceConfig)
class HausdorffDistanceLoss(SurfaceDistanceLoss):
    """The largest distance from one surface to the other."""

    def reduce(self, distances):
        return np.max(distances)
