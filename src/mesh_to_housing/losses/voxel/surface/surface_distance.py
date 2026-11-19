from abc import abstractmethod
from typing import Literal

import numpy as np

from ....geometry.outer_surface import nearest_distances, outer_surfaces
from ...base import Loss, implements
from ..base import VoxelLossConfig


class ChamferDistanceConfig(VoxelLossConfig):
    type: Literal["chamfer_distance"] = "chamfer_distance"


class HausdorffDistanceConfig(VoxelLossConfig):
    type: Literal["hausdorff_distance"] = "hausdorff_distance"


class SurfaceDistanceLoss(Loss):
    """A summary of the distances between the target surface and the construction's outer surface.
    Distances are divided by the target's longest side, so they keep their meaning at any target size.
    """

    def __call__(self, target, construction):
        grid = self.config.voxel_grid(target)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        if not construction_surface.any():
            # A finite value lets a greedy fit rank its first item. Infinity would make every first gain equal.
            return 1.0
        size = float(target.extents.max())
        return self.summary(nearest_distances(construction_surface, target_surface, grid.pitch) / size,
                            nearest_distances(target_surface, construction_surface, grid.pitch) / size)

    @abstractmethod
    def summary(self, to_target: np.ndarray, to_construction: np.ndarray) -> float:
        pass


@implements(ChamferDistanceConfig)
class ChamferDistanceLoss(SurfaceDistanceLoss):
    """The mean distance from each surface to the other, averaged over both directions."""

    def summary(self, to_target, to_construction):
        return float((to_target.mean() + to_construction.mean()) / 2)


@implements(HausdorffDistanceConfig)
class HausdorffDistanceLoss(SurfaceDistanceLoss):
    """The largest distance from either surface to the other."""

    def summary(self, to_target, to_construction):
        return float(max(to_target.max(), to_construction.max()))
