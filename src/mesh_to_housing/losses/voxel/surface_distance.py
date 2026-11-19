from abc import abstractmethod
from dataclasses import dataclass
from typing import Literal, get_args

import numpy as np

from ...geometry.volume import VoxelGrid, nearest_distances, outer_surfaces
from ..base import Loss
from .base import VoxelLossConfig


Direction = Literal["both", "to_target", "to_construction"]


@dataclass(frozen=True)
class SurfaceDistanceConfig(VoxelLossConfig):
    """The direction measures from the construction "to_target", from the target "to_construction", or "both"."""

    direction: Direction = "both"

    def __post_init__(self):
        if self.direction not in get_args(Direction):
            raise ValueError(f"direction must be one of {', '.join(get_args(Direction))}")


@dataclass(frozen=True)
class ChamferDistanceConfig(SurfaceDistanceConfig):
    def build(self):
        return ChamferDistanceLoss(self)


@dataclass(frozen=True)
class HausdorffDistanceConfig(SurfaceDistanceConfig):
    def build(self):
        return HausdorffDistanceLoss(self)


class SurfaceDistanceLoss(Loss):
    """A summary of the distances between the target surface and the construction's outer surface.
    Distances are divided by the target's longest side, so they keep their meaning at any target size.
    """

    def __call__(self, target, construction):
        grid = VoxelGrid.from_mesh(target, self.config.grid)
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
    def reduce(self, distances):
        pass


class ChamferDistanceLoss(SurfaceDistanceLoss):
    """The mean distance from one surface to the other."""

    def reduce(self, distances):
        return np.mean(distances)


class HausdorffDistanceLoss(SurfaceDistanceLoss):
    """The largest distance from one surface to the other."""

    def reduce(self, distances):
        return np.max(distances)
