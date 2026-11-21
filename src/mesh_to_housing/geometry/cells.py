"""Grid cells packed into single integer keys, so that a set of cells can be a sorted integer array."""
from typing import Callable, Sequence

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


def select_keys(key_lists: Sequence[CellKeys], keep: Callable[[CellKeys], np.ndarray]) -> list[CellKeys]:
    """Each list with only the keys where keep(keys) is true. keep is called once for all lists together."""
    if not len(key_lists):
        return []
    keys = np.concatenate(key_lists)
    kept = keep(keys)
    ends = np.cumsum([len(listed) for listed in key_lists])[:-1]
    return np.split(keys[kept], np.concatenate(([0], np.cumsum(kept)))[ends])


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


def candidate_matrix(key_lists: Sequence[CellKeys]):
    """A sparse matrix with one row per list of keys and one column per cell of a box around all of them,
    returned with that box. Both are None when the lists are empty.
    """
    from scipy.sparse import csr_matrix

    keys = np.concatenate(key_lists) if len(key_lists) else np.zeros(0, dtype=np.int64)
    if not len(keys):
        return None, None
    box = CellBox.around(keys)
    rows = np.repeat(np.arange(len(key_lists)), [len(listed) for listed in key_lists])
    matrix = csr_matrix((np.ones(len(keys), dtype=np.int32), (rows, box.numbers(keys))),
                        shape=(len(key_lists), box.size))
    return box, matrix
