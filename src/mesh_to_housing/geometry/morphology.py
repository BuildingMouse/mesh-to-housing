"""Growing sets of cell keys and finding their outer layer."""
from math import ceil
from typing import Sequence

import numpy as np

from ..utils.execution import map_chunks
from .cells import CellKeys, key_offsets

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


def ball_keys(pitch: float, radius: float) -> CellKeys:
    """Key offsets of the cells whose centers lie within radius of a cell's center."""
    reach = ceil(radius / pitch)
    return key_offsets(np.argwhere(ball_mask(pitch, radius)) - reach)


def dilate_each(key_lists: Sequence[CellKeys], pitch: float, radius: float) -> list[CellKeys]:
    """For each sorted list, the sorted keys of every cell whose center lies within radius of one of its cells.
    Lists are grown one at a time, so memory never exceeds what the largest list needs.
    """
    if radius < pitch:
        return list(key_lists)
    return map_chunks(_dilate_chunk, key_lists, ball_keys(pitch, radius))


def _dilate_chunk(key_lists, steps):
    return [np.unique((keys[None, :] + steps[:, None]).ravel()) for keys in key_lists]
