from typing import Literal

import numpy as np

from ....geometry.cells import cell_keys
from ....geometry.outer_surface import outer_solids
from ....geometry.surface import solid_normals, surface_roughness
from ...base import Loss, implements
from ..base import RoughnessConfig


class ExcessRoughnessConfig(RoughnessConfig):
    type: Literal["excess_roughness"] = "excess_roughness"


@implements(ExcessRoughnessConfig)
class ExcessRoughnessLoss(Loss):
    """How much rougher the construction's outer surface is than the target's outer surface."""

    def __call__(self, target, construction):
        from scipy.ndimage import binary_erosion, distance_transform_edt

        grid = self.config.voxel_grid(target)
        target_surface, solid, low = outer_solids(grid, construction)
        surface = solid & ~binary_erosion(solid)
        if not surface.any():
            return 0.0
        radius = self.config.roughness_radius_for(grid)
        cells = np.argwhere(surface)
        roughness = surface_roughness(surface, cells, solid_normals(solid, cells), grid.pitch, radius)
        nearest = distance_transform_edt(~target_surface, return_distances=False, return_indices=True)
        matched = np.stack([axis[tuple(cells.T)] for axis in nearest], axis=1) + low
        target_roughness = grid.surface.roughness(radius)[grid.surface.index_of(cell_keys(matched))]
        return float(np.maximum(roughness - target_roughness, 0.0).sum() / len(grid.surface))
