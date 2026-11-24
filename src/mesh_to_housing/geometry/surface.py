from functools import cached_property
from math import ceil

import numpy as np

from .cells import CellBox, CellKeys, cell_indices, cell_keys
from .morphology import ball_mask


class TargetSurface:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid
        self._near_masks = {}

    @cached_property
    def mask(self) -> np.ndarray:
        """The surface cells as a boolean array over the grid's box."""
        from scipy.ndimage import binary_erosion

        solid = self._grid.solid_mask
        return solid & ~binary_erosion(solid)

    @cached_property
    def keys(self) -> CellKeys:
        return cell_keys(np.argwhere(self.mask) + self._grid.box.low)

    @cached_property
    def indices(self) -> np.ndarray:
        return cell_indices(self.keys)

    def __len__(self) -> int:
        return len(self.keys)

    def contains(self, keys: CellKeys) -> np.ndarray:
        return self._grid.box.lookup(self.mask, keys)

    def near(self, keys: CellKeys, radius: float) -> np.ndarray:
        """Whether each cell's center lies within radius of a surface cell's center."""
        if radius not in self._near_masks:
            from scipy.ndimage import binary_dilation

            grid = self._grid
            reach = ceil(radius / grid.pitch)
            box = CellBox(grid.box.low - reach, grid.box.low + grid.box.shape - 1 + reach)
            grown = binary_dilation(np.pad(self.mask, reach), structure=ball_mask(grid.pitch, radius))
            self._near_masks[radius] = box, grown
        box, grown = self._near_masks[radius]
        return box.lookup(grown, keys)

    def index_of(self, keys: CellKeys) -> np.ndarray:
        """Where each of these surface cells sits in keys."""
        return np.searchsorted(self.keys, keys)

    @cached_property
    def normals(self) -> np.ndarray:
        return self._grid.outward_normals(self.indices)

    @cached_property
    def points(self) -> np.ndarray:
        """Points on the surface itself, half a cell outward from the centers of the surface cells."""
        grid = self._grid
        return grid.origin + self.indices * grid.pitch + self.normals * grid.pitch / 2
