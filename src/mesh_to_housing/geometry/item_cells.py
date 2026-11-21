from weakref import WeakKeyDictionary

import numpy as np

from .morphology import skin_cells


class ItemCells:
    def __init__(self, grid):
        self._grid = grid
        self._occupied = WeakKeyDictionary()
        self._skins = WeakKeyDictionary()

    def occupied(self, placement):
        cells = self._occupied.get(placement)
        if cells is None:
            cells = self._occupied[placement] = sample_occupied(self._grid, placement)
        return cells

    def skin(self, placement):
        cells = self._skins.get(placement)
        if cells is None:
            cells = self._skins[placement] = skin_cells(self.occupied(placement))
        return cells


def sample_occupied(grid, placement):
    world_low, world_high = _world_bounds(placement)
    low = np.ceil((world_low - grid.origin) / grid.pitch - 1e-9).astype(int)
    high = np.floor((world_high - grid.origin) / grid.pitch + 1e-9).astype(int)
    lengths = high - low + 1
    if np.any(lengths <= 0):
        return frozenset()
    if np.prod(lengths.astype(float)) > grid.config.max_cells:
        raise ValueError("Item grid is too large; increase voxel_pitch or max_cells")
    indices = np.indices(tuple(lengths)).reshape(3, -1).T + low
    points = grid.origin + indices * grid.pitch
    inside = placement.item.contains(((points - placement.center) @ placement.rotation) / placement.scale)
    return frozenset(map(tuple, indices[inside].tolist()))


def _world_bounds(placement):
    corners = np.array(np.meshgrid(*placement.item.bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    return corners.min(axis=0), corners.max(axis=0)
