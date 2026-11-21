"""Growing sets of cell keys and finding their outer layer."""
from math import ceil
from typing import Sequence

import numpy as np

from ..execution import map_chunks
from .cells import CellBox, CellKeys, key_offsets

_FACES = key_offsets(np.vstack((np.eye(3, dtype=int), -np.eye(3, dtype=int))))


def ball_mask(pitch: float, radius: float) -> np.ndarray:
    """Which cells of a cube around a center cell have their centers within radius of it."""
    cells = ceil(radius / pitch)
    offsets = np.indices((2 * cells + 1,) * 3) - cells
    return np.linalg.norm(offsets, axis=0) * pitch <= radius


def skin_keys(keys: CellKeys) -> CellKeys:
    """The cells of a sorted set that touch a cell outside the set through a face."""
    if not len(keys):
        return keys
    enclosed = np.ones(len(keys), dtype=bool)
    for face in _FACES:
        neighbors = keys + face
        position = np.minimum(np.searchsorted(keys, neighbors), len(keys) - 1)
        enclosed &= keys[position] == neighbors
    return keys[~enclosed]


def dilate_each(key_lists: Sequence[CellKeys], pitch: float, radius: float) -> list[CellKeys]:
    """For each list, the sorted keys of every cell whose center lies within radius of one of its cells.

    All lists are grown in one pass.
    """
    return map_chunks(_dilate_chunk, key_lists, pitch, radius)


def _dilate_chunk(key_lists, pitch, radius):
    reached, owners = _dilate_all(key_lists, pitch, radius)
    return _split_by_list(reached, owners, len(key_lists))


def _dilate_all(key_lists, pitch, radius):
    """The grown keys of all lists in sorted order, and the index of the list each key belongs to."""
    reach = ceil(radius / pitch)
    offsets = np.argwhere(ball_mask(pitch, radius)) - reach
    counts = [len(keys) for keys in key_lists]
    if not sum(counts):
        return np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.int64)
    keys = np.concatenate(key_lists)
    around = CellBox.around(keys)
    box = CellBox(around.low - reach, around.low + around.shape - 1 + reach)
    steps = (offsets[:, 0] * box.shape[1] + offsets[:, 1]) * box.shape[2] + offsets[:, 2]
    owners = np.repeat(np.arange(len(key_lists), dtype=np.int64), counts)
    numbered = np.unique((steps[:, None] + (owners * box.size + box.numbers(keys))[None, :]).ravel())
    return box.keys(numbered % box.size), numbered // box.size


def _split_by_list(values, owners, count):
    return np.split(values, np.searchsorted(owners, np.arange(1, count)))
