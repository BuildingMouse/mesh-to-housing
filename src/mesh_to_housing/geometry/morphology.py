from math import ceil

import numpy as np

_FACES = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def skin_cells(cells):
    enclosed = set(cells)
    for dx, dy, dz in _FACES:
        enclosed.intersection_update((x - dx, y - dy, z - dz) for x, y, z in cells)
    return cells - enclosed


def ball_mask(pitch, radius):
    cells = ceil(radius / pitch)
    offsets = np.indices((2 * cells + 1,) * 3) - cells
    return np.linalg.norm(offsets, axis=0) * pitch <= radius


def dilated_cells(cells, pitch, radius, max_cells):
    from scipy.ndimage import binary_dilation

    if not cells:
        return frozenset()
    indices = np.asarray(list(cells), dtype=int)
    reach = ceil(radius / pitch)
    low = indices.min(axis=0) - reach
    shape = indices.max(axis=0) + reach - low + 1
    if np.prod(shape.astype(float)) > max_cells:
        raise ValueError("Surface grid is too large; reduce surface_tolerance or increase voxel_pitch or max_cells")
    mask = np.zeros(shape, dtype=bool)
    mask[tuple((indices - low).T)] = True
    reached = np.argwhere(binary_dilation(mask, ball_mask(pitch, radius))) + low
    return frozenset(map(tuple, reached.tolist()))
