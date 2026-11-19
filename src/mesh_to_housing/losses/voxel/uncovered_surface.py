from dataclasses import dataclass
from math import ceil

import numpy as np

from ...geometry.volume import occupied_cells
from .base import CoverageSession, SurfaceToleranceConfig, VoxelLoss


@dataclass(frozen=True)
class UncoveredSurfaceConfig(SurfaceToleranceConfig):
    def build(self):
        return UncoveredSurfaceLoss(self)


class UncoveredSurfaceLoss(VoxelLoss):
    """Target surface area no item reaches, divided by the target surface area."""

    def session(self, target):
        grid = self.grid(target)
        tolerance = self.config.tolerance_for(target)

        def covered_surface(placement):
            return covered_surface_cells(grid, placement, tolerance)

        return CoverageSession(covered_surface, reference_count=len(grid.surface_cells))


def covered_surface_cells(grid, placement, tolerance):
    """Target surface cells that the item reaches within the tolerance."""
    from scipy.ndimage import binary_dilation

    occupied = occupied_cells(grid, placement)
    if not occupied:
        return frozenset()
    cells = np.array(list(occupied))
    ball = _ball(grid.pitch, tolerance)
    radius = ball.shape[0] // 2
    low = cells.min(axis=0) - radius
    reached = np.zeros(cells.max(axis=0) + radius - low + 1, dtype=bool)
    reached[tuple((cells - low).T)] = True
    reached = np.argwhere(binary_dilation(reached, ball)) + low

    surface, surface_low = grid.surface_mask
    local = reached - surface_low
    local = local[np.all((local >= 0) & (local < surface.shape), axis=1)]
    return frozenset(map(tuple, (local[surface[tuple(local.T)]] + surface_low).tolist()))


def _ball(pitch, radius):
    cells = ceil(radius / pitch)
    offsets = np.indices((2 * cells + 1,) * 3) - cells
    return np.linalg.norm(offsets, axis=0) * pitch <= radius
