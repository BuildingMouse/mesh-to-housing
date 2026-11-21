from functools import cached_property

import numpy as np


class TargetSurface:
    def __init__(self, grid):
        self._grid = grid

    @cached_property
    def cells(self):
        mask, low = self._grid.surface_mask
        return np.argwhere(mask) + low

    def __len__(self):
        return len(self.cells)

    @cached_property
    def normals(self):
        from scipy.ndimage import gaussian_filter

        grid = self._grid
        low = grid.indices.min(axis=0) - 2
        solid = np.zeros(grid.indices.max(axis=0) - low + 3)
        solid[tuple((grid.indices - low).T)] = 1.0
        gradient = np.gradient(gaussian_filter(solid, sigma=1.0))
        local = tuple((self.cells - low).T)
        normals = -np.stack([component[local] for component in gradient], axis=1)
        lengths = np.linalg.norm(normals, axis=1, keepdims=True)
        return np.where(lengths > 0, normals / np.where(lengths > 0, lengths, 1), (0.0, 0.0, 1.0))

    @cached_property
    def points(self):
        # Cell centers sit inside the target; anchors should touch its boundary.
        return self._grid.origin + self.cells * self._grid.pitch + self.normals * self._grid.pitch / 2
