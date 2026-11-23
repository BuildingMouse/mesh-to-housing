"""Which grid cells placements occupy."""
from collections import Counter
from typing import Iterator, Optional, Sequence
from weakref import WeakKeyDictionary

import numpy as np

from ..utils.execution import map_chunks, share, worker_count
from ..placement import Placement
from .cells import CellKeys, batches, cell_keys
from .morphology import dilate_each, skin_keys


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

    def occupied_by_each(self, placements: Sequence[Placement]) -> Iterator[CellKeys]:
        """The cells each placement occupies, worked out one placement at a time as they are read."""
        placements = list(placements)
        patterns = _SharedPatterns(self, placements)
        self._sample_on_workers(placements, patterns)
        return (patterns.occupied(placement) for placement in placements)

    def skins_of_each(self, placements: Sequence[Placement]) -> Iterator[CellKeys]:
        """Each placement's skin, the outer layer of its cells, worked out one placement at a time as they are read."""
        placements = list(placements)
        patterns = _SharedPatterns(self, placements)
        self._sample_on_workers(placements, patterns)
        return (patterns.skin(placement) for placement in placements)

    def dilated_each(self, placements: Sequence[Placement], radius: float, *,
                     skin_only: bool = False) -> Iterator[CellKeys]:
        """Each placement's cells, or only its skin, grown by radius. Placements that share a pattern are grown
        once, and the rest in batches as they are read.
        """
        placements = list(placements)
        patterns = _SharedPatterns(self, placements)
        self._sample_on_workers(placements, patterns)
        return self._dilated(placements, patterns, radius, skin_only)

    def _dilated(self, placements, patterns, radius, skin_only):
        for batch in batches(placements, 4096):
            found = [patterns.cell_and_pattern_key(placement) for placement in batch]
            off_center = [patterns.skin(placement) if skin_only else patterns.occupied(placement)
                          for placement, where in zip(batch, found) if where is None]
            grown = iter(dilate_each(off_center, self._grid.pitch, radius))
            for placement, where in zip(batch, found):
                if where is None:
                    yield next(grown)
                else:
                    yield where[0] + patterns.dilated(where, placement, radius, skin_only)

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
    Placements of the same item, rotation and scale that sit at the same spot within their cells occupy the same
    cells, just shifted. So we sample one pattern for each such group and shift it into place. A placement on a
    cell center always uses a pattern, and one elsewhere uses a pattern only when another placement in the batch
    shares it.
    """

    def __init__(self, cells: ItemCells, placements: Sequence[Placement]):
        self._cells = cells
        self._grid = cells._grid
        self._occupied_patterns = {}
        self._skin_patterns = {}
        self._dilated_patterns = {}
        self._found = {}
        if placements:
            keys, spots = _cells_and_spots(self._grid, np.array([placement.center for placement in placements]))
            found = [(int(key), (placement.item, placement.rotation.tobytes(), placement.scale, spot.tobytes()))
                     for placement, key, spot in zip(placements, keys, spots)]
            sharing = Counter(pattern for _, pattern in found)
            centered = ~spots.any(axis=1)
            self._found = {placement: where for placement, where, on_center in zip(placements, found, centered)
                           if on_center or sharing[where[1]] > 1}

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

    def dilated(self, found: tuple[int, tuple], placement: Placement, radius: float, skin_only: bool) -> CellKeys:
        cell, pattern = found
        key = (pattern, radius, skin_only)
        if key not in self._dilated_patterns:
            keys = self.skin(placement) if skin_only else self.occupied(placement)
            # Pattern keys are offsets, which don't decode as cells, so grow the placed copy and shift it back.
            self._dilated_patterns[key] = dilate_each([keys], self._grid.pitch, radius)[0] - cell
        return self._dilated_patterns[key]

    def _occupied_pattern(self, pattern: tuple, placement: Placement) -> CellKeys:
        if pattern not in self._occupied_patterns:
            self._occupied_patterns[pattern] = _pattern_at(self._grid, placement, np.frombuffer(pattern[3]))
        return self._occupied_patterns[pattern]

    def cell_and_pattern_key(self, placement: Placement) -> Optional[tuple[int, tuple]]:
        """The key of the cell the placement falls in and a key for its pattern, or None if it has no pattern."""
        return self._found.get(placement)


def _cells_and_spots(grid: "VoxelGrid", centers: np.ndarray) -> tuple[CellKeys, np.ndarray]:
    """The nearest cell to each center, and where the center sits relative to that cell's center, in cells.
    Spots are rounded, so that placements on one lattice get equal spots despite rounding errors.
    """
    position = (centers - grid.origin) / grid.pitch
    cells = np.round(position)
    spots = np.round(position - cells, 12)
    spots[np.abs(spots) <= 1e-9] = 0.0
    return cell_keys(cells), spots


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


def _pattern_at(grid, placement, spot):
    """The placement's cells when it sits at this spot of the cell at the grid's origin, as offset keys."""
    moved = Placement(placement.item, grid.origin + spot * grid.pitch, placement.rotation, placement.scale)
    return sample_occupied(grid, moved) - cell_keys(np.zeros(3))[0]


def _world_bounds(placement):
    corners = np.array(np.meshgrid(*placement.item.bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    return corners.min(axis=0), corners.max(axis=0)


def _sample_chunk(placements, grid):
    grid = grid.get()
    return [(keys, skin_keys(keys)) for keys in (sample_occupied(grid, placement) for placement in placements)]
