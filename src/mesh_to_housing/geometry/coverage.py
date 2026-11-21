import numpy as np

from .morphology import dilated_cells


def covered_surface_cells(grid, placement, tolerance, *, skin_only=False):
    cells = grid.item_cells.skin(placement) if skin_only else grid.item_cells.occupied(placement)
    return dilated_cells(cells, grid.pitch, tolerance, grid.config.max_cells) & grid.surface_cells


def uncovered_surface_cells(grid, placements, tolerance, *, skin_only=False):
    covered = set()
    for placement in placements:
        covered.update(covered_surface_cells(grid, placement, tolerance, skin_only=skin_only))
    return grid.surface_cells - covered


def excess_surface_cells(grid, placement, tolerance):
    cells = grid.item_cells.skin(placement)
    if not cells:
        return frozenset()
    indices = np.asarray(list(cells), dtype=int)
    outside = indices[grid.outside_distance(indices) > tolerance]
    return frozenset(map(tuple, outside.tolist()))
