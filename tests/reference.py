"""Slow, obvious versions of the voxel measurements, to check the fast code against."""
from math import ceil

import numpy as np
import pytest

from mesh_to_housing.geometry.cells import cell_indices

FACES = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def as_cells(keys):
    return frozenset(map(tuple, cell_indices(keys).tolist()))


def sampled_cells(grid, placement):
    """The grid cells whose centers lie inside the placed item, found by testing every cell in its box."""
    corners = np.array(np.meshgrid(*placement.item.bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    low = np.ceil((corners.min(axis=0) - grid.origin) / grid.pitch - 1e-9).astype(int)
    high = np.floor((corners.max(axis=0) - grid.origin) / grid.pitch + 1e-9).astype(int)
    lengths = high - low + 1
    if np.any(lengths <= 0):
        return frozenset()
    cells = np.indices(tuple(lengths)).reshape(3, -1).T + low
    points = grid.origin + cells * grid.pitch
    inside = placement.item.contains(((points - placement.center) @ placement.rotation) / placement.scale)
    return frozenset(map(tuple, cells[inside].tolist()))


def skin(cells):
    return frozenset(cell for cell in cells
                     if any(tuple(np.asarray(cell) + face) not in cells for face in FACES))


def expanded(cells, pitch, tolerance):
    reach = ceil(tolerance / pitch)
    offsets = np.indices((2 * reach + 1,) * 3).reshape(3, -1).T - reach
    offsets = offsets[np.linalg.norm(offsets, axis=1) * pitch <= tolerance]
    return frozenset(tuple(np.asarray(cell) + offset) for cell in cells for offset in offsets)


ADD_AND_REMOVE = [(True, 0), (True, 2), (True, 1), (False, 0), (True, 4), (False, 2), (False, 1), (False, 4)]


def follow(session, placements, counted, reference, penalty=False, weigh=len):
    """Add and remove placements in a fixed order. After each step, check the session's value and every candidate's
    gain against set arithmetic on the cells that counted gives for each placement, weighed by weigh.
    """
    scorer = session.scorer(placements)
    placed = []
    for adding, index in ADD_AND_REMOVE:
        if adding:
            placed.append(placements[index])
            session.add(placements[index])
        else:
            placed.remove(placements[index])
            session.remove(placements[index])
        union = frozenset().union(*(counted(placement) for placement in placed))
        share = weigh(union) / reference
        assert session.value() == pytest.approx(share if penalty else 1.0 - share, abs=1e-12)
        gains = [(-1 if penalty else 1) * weigh(counted(placement) - union) / reference for placement in placements]
        np.testing.assert_allclose(scorer.gains(), gains, atol=1e-12, rtol=0)
        np.testing.assert_allclose([session.gain(placement) for placement in placements], gains, atol=1e-12, rtol=0)
