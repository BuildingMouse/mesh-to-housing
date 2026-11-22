"""Which grid cells placements occupy."""
from typing import Optional, Sequence
from weakref import WeakKeyDictionary

import numpy as np

from ..utils.execution import map_chunks, share, worker_count
from ..placement import Placement
from .cells import CellKeys, cell_keys
from .morphology import skin_keys


class ItemCells:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid
        self._occupied = WeakKeyDictionary()
        self._skins = WeakKeyDictionary()

    def _sampled(self, placement: Placement) -> CellKeys:
        """Samples one placement's cells and remembers them for as long as the placement exists."""
        keys = self._occupied.get(placement)
        if keys is None:
            keys = self._occupied[placement] = sample_occupied(self._grid, placement)
        return keys

    def _sampled_skin(self, placement: Placement) -> CellKeys:
        """The outer layer of one placement's cells, remembered the same way."""
        keys = self._skins.get(placement)
        if keys is None:
            keys = self._skins[placement] = skin_keys(self._sampled(placement))
        return keys

    def occupied_by_each(self, placements: Sequence[Placement]) -> list[CellKeys]:
        """Returns the cells each placement occupies."""
        patterns = _SharedPatterns(self)
        placements = list(placements)
        self._sample_on_workers(placements, patterns)
        return [patterns.occupied(placement) for placement in placements]

    def skins_of_each(self, placements: Sequence[Placement]) -> list[CellKeys]:
        """Returns each placement's skin: the outer layer of its cells."""
        patterns = _SharedPatterns(self)
        placements = list(placements)
        self._sample_on_workers(placements, patterns)
        return [patterns.skin(placement) for placement in placements]

    def _sample_on_workers(self, placements: list[Placement], patterns: "_SharedPatterns") -> None:
        if worker_count() <= 1:
            return
        missing = [placement for placement in placements
                   if placement not in self._occupied and patterns.cell_and_pattern_key(placement) is None]
        if len(missing) >= 8:
            for placement, (keys, skin) in zip(missing, map_chunks(_sample_chunk, missing,
                                                                   share(self._grid))):
                self._occupied[placement] = keys
                self._skins[placement] = skin


class _SharedPatterns:
    """Shared cell patterns for one batch of placements.
    A placement sitting exactly on a cell center occupies the same cells wherever it is, just shifted. So we
    sample one pattern per item, rotation and scale, and shift it into place.
    """

    def __init__(self, cells: ItemCells):
        self._cells = cells
        self._grid = cells._grid
        self._occupied_patterns = {}
        self._skin_patterns = {}

    def occupied(self, placement: Placement) -> CellKeys:
        found = self.cell_and_pattern_key(placement)
        if found is None:
            return self._cells._sampled(placement)
        cell, pattern = found
        return cell + self._occupied_pattern(pattern, placement)

    def skin(self, placement: Placement) -> CellKeys:
        found = self.cell_and_pattern_key(placement)
        if found is None:
            return self._cells._sampled_skin(placement)
        cell, pattern = found
        if pattern not in self._skin_patterns:
            self._skin_patterns[pattern] = skin_keys(self._occupied_pattern(pattern, placement))
        return cell + self._skin_patterns[pattern]

    def _occupied_pattern(self, pattern: tuple, placement: Placement) -> CellKeys:
        if pattern not in self._occupied_patterns:
            self._occupied_patterns[pattern] = _pattern_at_origin(self._grid, placement)
        return self._occupied_patterns[pattern]

    def cell_and_pattern_key(self, placement: Placement) -> Optional[tuple[int, tuple]]:
        """Returns the key of the cell the placement sits on and a key for its pattern, or None if it's off
        center.
        """
        position = (placement.center - self._grid.origin) / self._grid.pitch
        cell = np.round(position)
        if np.any(np.abs(position - cell) > 1e-9):
            return None
        return cell_keys(cell)[0], (placement.item, placement.rotation.tobytes(), placement.scale)


def sample_occupied(grid: "VoxelGrid", placement: Placement) -> CellKeys:
    """Finds the cells whose centers lie inside the placed item, as sorted keys.
    Counting cells by their centers measures the item's volume without bias at any pitch.
    """
    world_low, world_high = _world_bounds(placement)
    low = np.ceil((world_low - grid.origin) / grid.pitch - 1e-9).astype(int)
    high = np.floor((world_high - grid.origin) / grid.pitch + 1e-9).astype(int)
    lengths = high - low + 1
    if np.any(lengths <= 0):
        return np.zeros(0, dtype=np.int64)
    if np.prod(lengths.astype(float)) > grid.config.max_cells:
        raise ValueError("Item grid is too large; increase voxel_pitch or max_cells")
    indices = np.indices(tuple(lengths)).reshape(3, -1).T + low
    points = grid.origin + indices * grid.pitch
    inside = placement.item.contains(((points - placement.center) @ placement.rotation) / placement.scale)
    return cell_keys(indices[inside])


def _pattern_at_origin(grid, placement):
    at_origin = Placement(placement.item, grid.origin, placement.rotation, placement.scale)
    return sample_occupied(grid, at_origin) - cell_keys(np.zeros(3))[0]


def _world_bounds(placement):
    corners = np.array(np.meshgrid(*placement.item.bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    return corners.min(axis=0), corners.max(axis=0)


def _sample_chunk(placements, grid):
    grid = grid.get()
    return [(keys, skin_keys(keys)) for keys in (sample_occupied(grid, placement) for placement in placements)]
