"""Grid cells packed into single integer keys, so that a set of cells can be a sorted integer array."""
from itertools import islice
from typing import Callable, Iterable, Iterator, Optional

import numpy as np

# Sorted int64 cell keys. Many cell sets are usually passed as a list of these, one per placement or candidate.
CellKeys = np.ndarray
# A function that returns the weight of each cell it's given.
CellWeights = Callable[[CellKeys], np.ndarray]

_BITS = 20
_OFFSET = 1 << (_BITS - 1)
_MASK = (1 << _BITS) - 1


def key_offsets(offsets: np.ndarray) -> CellKeys:
    """Keys for offsets between cells. Adding an offset's key to a cell's key moves the cell by that offset."""
    offsets = np.asarray(offsets, dtype=np.int64).reshape(-1, 3)
    return (offsets[:, 0] << 2 * _BITS) + (offsets[:, 1] << _BITS) + offsets[:, 2]


def cell_keys(indices: np.ndarray) -> CellKeys:
    """The key of each cell. Keys sort in the same order as the cells' (x, y, z) indices."""
    return key_offsets(np.asarray(indices, dtype=np.int64).reshape(-1, 3) + _OFFSET)


def cell_indices(keys: CellKeys) -> np.ndarray:
    keys = np.asarray(keys, dtype=np.int64)
    return np.stack([(keys >> 2 * _BITS) & _MASK, (keys >> _BITS) & _MASK, keys & _MASK], axis=1) - _OFFSET


def contains_sorted(sorted_keys: CellKeys, keys: CellKeys) -> np.ndarray:
    """Whether each key appears in a sorted array of keys."""
    if not len(sorted_keys):
        return np.zeros(len(keys), dtype=bool)
    position = np.minimum(np.searchsorted(sorted_keys, keys), len(sorted_keys) - 1)
    return sorted_keys[position] == keys


def batches(values: Iterable, size: int) -> Iterator[list]:
    """The values in lists of up to size, in order."""
    values = iter(values)
    while batch := list(islice(values, size)):
        yield batch


def key_batches(key_lists: Iterable[CellKeys], size: int) -> Iterator[list[CellKeys]]:
    """The lists in batches of at most size keys, in order. A list longer than size makes a batch of its own."""
    batch, held = [], 0
    for keys in key_lists:
        if batch and held + len(keys) > size:
            yield batch
            batch, held = [], 0
        batch.append(keys)
        held += len(keys)
    if batch:
        yield batch


def select_keys(key_lists: Iterable[CellKeys], keep: Callable[[CellKeys], np.ndarray],
                size: int = 1 << 20) -> Iterator[CellKeys]:
    """Each list with only the keys where keep(keys) is true. keep is called once per batch of about size keys."""
    for lists in key_batches(key_lists, size):
        keys = np.concatenate(lists)
        kept = keep(keys)
        ends = np.cumsum([len(listed) for listed in lists])[:-1]
        yield from np.split(keys[kept], np.concatenate(([0], np.cumsum(kept)))[ends])


class CellBox:
    """A box of cells, numbered from 0 so that a cell's number can index an array."""

    def __init__(self, low: np.ndarray, high: np.ndarray):
        self.low = np.asarray(low, dtype=np.int64)
        self.shape = np.asarray(high, dtype=np.int64) - self.low + 1
        self.size = int(np.prod(self.shape))

    @classmethod
    def around(cls, keys: CellKeys) -> "CellBox":
        indices = cell_indices(keys)
        return cls(indices.min(axis=0), indices.max(axis=0))

    def padded(self, cells: int) -> "CellBox":
        return CellBox(self.low - cells, self.low + self.shape - 1 + cells)

    def clipped(self, indices: np.ndarray) -> tuple[np.ndarray, ...]:
        return tuple(np.clip(np.asarray(indices) - self.low, 0, self.shape - 1).T)

    def numbers(self, keys: CellKeys) -> np.ndarray:
        """The number of each cell in the box, or -1 for cells outside it."""
        local = cell_indices(keys) - self.low
        inside = np.all((local >= 0) & (local < self.shape), axis=1)
        numbers = (local[:, 0] * self.shape[1] + local[:, 1]) * self.shape[2] + local[:, 2]
        return np.where(inside, numbers, -1)

    def keys(self, numbers: np.ndarray) -> CellKeys:
        """The keys of the cells with these numbers."""
        return cell_keys(np.stack(np.unravel_index(numbers, tuple(self.shape)), axis=1) + self.low)

    def renumbered(self, numbers: np.ndarray, box: "CellBox") -> np.ndarray:
        """The numbers that cells of this box have in a larger box that holds it."""
        x, y, z = np.unravel_index(numbers, tuple(self.shape))
        shift = self.low - box.low
        return ((x + shift[0]) * box.shape[1] + y + shift[1]) * box.shape[2] + z + shift[2]

    def lookup(self, mask: np.ndarray, keys: CellKeys) -> np.ndarray:
        """Whether each cell is set in a boolean mask that covers this box."""
        numbers = self.numbers(keys)
        found = np.zeros(len(numbers), dtype=bool)
        inside = numbers >= 0
        found[inside] = mask.ravel()[numbers[inside]]
        return found


class CellHolders:
    """Which candidates hold each cell, over a box around all their cells.
    It reads the candidates a chunk at a time and stores each chunk's cells as compact numbers within the chunk's
    own box, so full keys only ever exist for one chunk.
    """

    def __init__(self, key_lists: Iterable[CellKeys], count: int, keys_per_chunk: int = 1 << 20):
        self.count = count
        self.lengths = np.zeros(count, dtype=np.int64)
        self.box: Optional[CellBox] = None
        chunks, start, low, high = [], 0, None, None
        for lists in key_batches(key_lists, keys_per_chunk):
            self.lengths[start:start + len(lists)] = [len(keys) for keys in lists]
            keys = np.concatenate(lists)
            if len(keys):
                box = CellBox.around(keys)
                chunks.append((start, len(lists), box, box.numbers(keys).astype(_index_type(box.size))))
                top = box.low + box.shape - 1
                low = box.low if low is None else np.minimum(low, box.low)
                high = top if high is None else np.maximum(high, top)
            start += len(lists)
        if low is None:
            return
        self.box = CellBox(low, high)
        per_cell = np.zeros(self.box.size, dtype=np.int64)
        for position, (start, size, box, numbers) in enumerate(chunks):
            numbers = box.renumbered(numbers, self.box).astype(_index_type(self.box.size))
            chunks[position] = (start, size, numbers)
            per_cell += np.bincount(numbers, minlength=self.box.size)
        self._starts = np.concatenate(([0], np.cumsum(per_cell)))
        del per_cell
        self._holders = np.empty(int(self._starts[-1]), dtype=_index_type(count))
        free = self._starts[:-1].copy()
        for position, (start, size, numbers) in enumerate(chunks):
            chunks[position] = None
            holders = np.repeat(np.arange(start, start + size, dtype=self._holders.dtype),
                                self.lengths[start:start + size])
            order = np.argsort(numbers)
            numbers, holders = numbers[order], holders[order]
            first = np.flatnonzero(np.r_[True, numbers[1:] != numbers[:-1]])
            runs = np.diff(np.r_[first, len(numbers)])
            self._holders[free[numbers] + np.arange(len(numbers)) - np.repeat(first, runs)] = holders
            free[numbers[first]] += runs

    def counts(self, keys: CellKeys, weights: Optional[CellWeights] = None) -> np.ndarray:
        """For each candidate, how many of these distinct cells it holds, or their total weight when weights are
        given.
        """
        if self.box is None:
            return np.zeros(self.count, dtype=np.int64 if weights is None else float)
        numbers = self.box.numbers(keys)
        inside = numbers >= 0
        numbers = numbers[inside]
        starts = self._starts[numbers]
        sizes = self._starts[numbers + 1] - starts
        positions = np.repeat(starts - (np.cumsum(sizes) - sizes), sizes) + np.arange(sizes.sum())
        if weights is None:
            return np.bincount(self._holders[positions], minlength=self.count)
        return np.bincount(self._holders[positions], weights=np.repeat(weights(keys[inside]), sizes),
                           minlength=self.count)

    def totals(self, weights: Optional[CellWeights] = None) -> np.ndarray:
        """For each candidate, how many cells it holds, or their total weight when weights are given."""
        if weights is None:
            return self.lengths
        if self.box is None:
            return np.zeros(self.count)
        return self.counts(self.box.keys(np.flatnonzero(np.diff(self._starts))), weights)


def _index_type(size: int):
    return np.int32 if size < 2 ** 31 else np.int64
