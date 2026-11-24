from typing import Literal, Optional

import numpy as np

from ....geometry.cells import cell_keys
from ....geometry.outer_surface import outer_solids
from ....geometry.surface import solid_normals, surface_roughness
from ....utils.values import PositiveFloat
from ...base import Loss, implements
from ..base import VoxelLossConfig


class ExcessRoughnessConfig(VoxelLossConfig):
    type: Literal["excess_roughness"] = "excess_roughness"
    roughness_radius: Optional[PositiveFloat] = None


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
        radius = 2 * grid.pitch if self.config.roughness_radius is None else self.config.roughness_radius
        cells = np.argwhere(surface)
        roughness = surface_roughness(surface, cells, solid_normals(solid, cells), grid.pitch, radius)
        nearest = distance_transform_edt(~target_surface, return_distances=False, return_indices=True)
        matched = np.stack([axis[tuple(cells.T)] for axis in nearest], axis=1) + low
        target_roughness = grid.surface.roughness(radius)[grid.surface.index_of(cell_keys(matched))]
        return float(np.maximum(roughness - target_roughness, 0.0).sum() / len(grid.surface))
