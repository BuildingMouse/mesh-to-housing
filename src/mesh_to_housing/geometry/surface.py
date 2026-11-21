from functools import cached_property

import numpy as np

from .cells import CellKeys, cell_indices, cell_keys


class TargetSurface:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid

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
