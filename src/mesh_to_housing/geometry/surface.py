from functools import cached_property
from math import ceil

import numpy as np

from .cells import CellBox, CellKeys, cell_indices, cell_keys
from .morphology import ball_mask


class TargetSurface:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid
        self._near_masks = {}
        self._thickness = {}
        self._roughness = {}

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

    def thickness(self, radius: float) -> np.ndarray:
        """How thick the target is around each surface cell, in target units. It finds the deepest point inside the
        target within radius of the cell and doubles it, so parts thicker than twice radius read as about twice
        radius thick.
        """
        if radius not in self._thickness:
            from scipy.ndimage import maximum_filter

            grid = self._grid
            footprint = ball_mask(grid.pitch, max(radius, grid.pitch))
            deepest = maximum_filter(grid.inner_depth, footprint=footprint, mode="constant")
            thickness = 2.0 * deepest[tuple((self.indices - grid.box.low).T)] * grid.pitch
            thickness.flags.writeable = False
            self._thickness[radius] = thickness
        return self._thickness[radius]

    def roughness(self, radius: float) -> np.ndarray:
        if radius not in self._roughness:
            grid = self._grid
            values = surface_roughness(self.mask, self.indices - grid.box.low, self.normals, grid.pitch, radius)
            values.flags.writeable = False
            self._roughness[radius] = values
        return self._roughness[radius]

    @cached_property
    def points(self) -> np.ndarray:
        """Points on the surface itself, half a cell outward from the centers of the surface cells."""
        grid = self._grid
        return grid.origin + self.indices * grid.pitch + self.normals * grid.pitch / 2


def surface_roughness(mask: np.ndarray, cells: np.ndarray, normals: np.ndarray, pitch: float,
                      radius: float) -> np.ndarray:
    """How much a surface bends around each of its cells: 0 on a flat face, rising toward 1 at sharp edges and
    small details.

    It looks at the outward normals of the surface cells within radius and measures how far they are from all
    lying along one line. The direction along that line doesn't matter, so the two sides of a thin flat part, whose
    normals point opposite ways, still count as flat.
    """
    from scipy.ndimage import convolve

    ball = ball_mask(pitch, max(radius, pitch)).astype(float)
    at_cells = tuple(np.asarray(cells, dtype=int).T)
    count = convolve(mask.astype(float), ball, mode="constant")[at_cells]
    spread = np.zeros((len(normals), 3, 3))
    field = np.zeros(mask.shape)
    for row in range(3):
        for column in range(row, 3):
            field[at_cells] = normals[:, row] * normals[:, column]
            spread[:, row, column] = spread[:, column, row] = convolve(field, ball, mode="constant")[at_cells] / count
    # The largest eigenvalue is 1 when the normals lie along one line and 1/3 when they point every way.
    largest = np.linalg.eigvalsh(spread)[:, -1]
    return np.clip(1.5 * (1.0 - largest), 0.0, 1.0)
