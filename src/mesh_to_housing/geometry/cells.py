"""Grid cells packed into single integer keys, so that a set of cells can be a sorted integer array."""
from itertools import islice
from typing import Callable, Iterable, Iterator, Optional

import numpy as np

# Sorted int64 cell keys. Many cell sets are usually passed as a list of these, one per placement or candidate.
CellKeys = np.ndarray

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


def select_keys(key_lists: Iterable[CellKeys], keep: Callable[[CellKeys], np.ndarray],
                batch: int = 4096) -> Iterator[CellKeys]:
    """Each list with only the keys where keep(keys) is true. keep is called once per batch of lists."""
    for lists in batches(key_lists, batch):
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

    def numbers(self, keys: CellKeys) -> np.ndarray:
        """The number of each cell in the box, or -1 for cells outside it."""
        local = cell_indices(keys) - self.low
        inside = np.all((local >= 0) & (local < self.shape), axis=1)
        numbers = (local[:, 0] * self.shape[1] + local[:, 1]) * self.shape[2] + local[:, 2]
        return np.where(inside, numbers, -1)

    def keys(self, numbers: np.ndarray) -> CellKeys:
        """The keys of the cells with these numbers."""
        return cell_keys(np.stack(np.unravel_index(numbers, tuple(self.shape)), axis=1) + self.low)

    def lookup(self, mask: np.ndarray, keys: CellKeys) -> np.ndarray:
        """Whether each cell is set in a boolean mask that covers this box."""
        numbers = self.numbers(keys)
        found = np.zeros(len(numbers), dtype=bool)
        inside = numbers >= 0
        found[inside] = mask.ravel()[numbers[inside]]
        return found


class CellHolders:
    """Which candidates hold each cell, over a box around all their cells.
    It reads the candidates a chunk at a time, so it never holds more than one compact copy of their cells.
    """

    def __init__(self, key_lists: Iterable[CellKeys], count: int, chunk: int = 4096):
        self.count = count
        self.lengths = np.zeros(count, dtype=np.int64)
        self.box: Optional[CellBox] = None
        chunks, low, high = [], None, None
        for start, lists in zip(range(0, count, chunk), batches(key_lists, chunk)):
            self.lengths[start:start + len(lists)] = [len(keys) for keys in lists]
            keys = np.concatenate(lists)
            if len(keys):
                indices = cell_indices(keys)
                low = indices.min(axis=0) if low is None else np.minimum(low, indices.min(axis=0))
                high = indices.max(axis=0) if high is None else np.maximum(high, indices.max(axis=0))
            chunks.append(keys)
        if low is None:
            return
        self.box = CellBox(low, high)
        per_cell = np.zeros(self.box.size, dtype=np.int64)
        for position, keys in enumerate(chunks):
            chunks[position] = numbers = self.box.numbers(keys).astype(_index_type(self.box.size))
            per_cell += np.bincount(numbers, minlength=self.box.size)
        self._starts = np.concatenate(([0], np.cumsum(per_cell)))
        del per_cell
        self._holders = np.empty(int(self._starts[-1]), dtype=_index_type(count))
        free = self._starts[:-1].copy()
        for position, numbers in enumerate(chunks):
            chunks[position] = None
            if not len(numbers):
                continue
            lengths = self.lengths[position * chunk:(position + 1) * chunk]
            holders = np.repeat(np.arange(position * chunk, position * chunk + len(lengths),
                                          dtype=self._holders.dtype), lengths)
            order = np.argsort(numbers)
            numbers, holders = numbers[order], holders[order]
            first = np.flatnonzero(np.r_[True, numbers[1:] != numbers[:-1]])
            runs = np.diff(np.r_[first, len(numbers)])
            self._holders[free[numbers] + np.arange(len(numbers)) - np.repeat(first, runs)] = holders
            free[numbers[first]] += runs

    def counts(self, keys: CellKeys) -> np.ndarray:
        """How many of these distinct keys each candidate holds."""
        if self.box is None:
            return np.zeros(self.count, dtype=np.int64)
        numbers = self.box.numbers(keys)
        numbers = numbers[numbers >= 0]
        starts = self._starts[numbers]
        sizes = self._starts[numbers + 1] - starts
        positions = np.repeat(starts - (np.cumsum(sizes) - sizes), sizes) + np.arange(sizes.sum())
        return np.bincount(self._holders[positions], minlength=self.count)


def _index_type(size: int):
    return np.int32 if size < 2 ** 31 else np.int64
