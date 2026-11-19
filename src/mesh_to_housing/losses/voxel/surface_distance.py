from abc import abstractmethod
from dataclasses import dataclass

from ...geometry.volume import VoxelGrid, nearest_distances, outer_surfaces
from ..base import Loss
from .base import VoxelLossConfig


@dataclass(frozen=True)
class ChamferDistanceConfig(VoxelLossConfig):
    def build(self):
        return ChamferDistanceLoss(self)


@dataclass(frozen=True)
class HausdorffDistanceConfig(VoxelLossConfig):
    def build(self):
        return HausdorffDistanceLoss(self)


class SurfaceDistanceLoss(Loss):
    """A summary of the distances between the target surface and the construction's outer surface.
    Distances are divided by the target's diam, so they keep their meaning at any target size.
    """

    def __call__(self, target, construction):
        grid = VoxelGrid.from_mesh(target, self.config.grid)
        target_surface, construction_surface = outer_surfaces(grid, construction)
        if not construction_surface.any():
            # A finite value lets a greedy fit rank its first item. Infinity would make every first gain equal.
            return 1.0
        size = float(target.extents.max())
        return self.summary(nearest_distances(construction_surface, target_surface, grid.pitch) / size,
                            nearest_distances(target_surface, construction_surface, grid.pitch) / size)

    @abstractmethod
    def summary(self, to_target, to_construction):
        pass


class ChamferDistanceLoss(SurfaceDistanceLoss):
    """The mean distance from each surface to the other, averaged over both directions."""

    def summary(self, to_target, to_construction):
        return float((to_target.mean() + to_construction.mean()) / 2)


class HausdorffDistanceLoss(SurfaceDistanceLoss):
    """The largest distance from either surface to the other."""

    def summary(self, to_target, to_construction):
        return float(max(to_target.max(), to_construction.max()))
