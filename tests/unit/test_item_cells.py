import multiprocessing

import numpy as np
import pytest

from mesh_to_housing import Execution, Placement
from mesh_to_housing.geometry.item_cells import _SharedPatterns
from mesh_to_housing.geometry.voxel_grid import VoxelGrid

from ..reference import as_cells, expanded, sampled_cells, skin


def test_cells_and_skins_match_sampling(grid, placements):
    occupied = grid.item_cells.occupied_by_each(placements)
    skins = grid.item_cells.skins_of_each(placements)
    for placement, keys, skin_keys in zip(placements, occupied, skins):
        expected = sampled_cells(grid, placement)
        assert np.all(np.diff(keys) > 0)
        assert as_cells(keys) == expected
        assert as_cells(skin_keys) == skin(expected)


def test_placements_at_one_spot_off_center_share_a_pattern(grid, placements):
    turned = placements[1]
    spot = np.array([0.3, 0.25, -0.4])
    lattice = [Placement(turned.item, grid.origin + (np.array(cell) + spot) * grid.pitch, turned.rotation, 1.0)
               for cell in ((2, 3, 2), (3, 3, 2), (2, 4, 3))]
    assert _SharedPatterns(grid.item_cells, lattice).cell_and_pattern_key(lattice[0]) is not None
    radius = grid.pitch * 1.1
    surface = skin(frozenset(map(tuple, grid.indices)))
    occupied = grid.item_cells.occupied_by_each(lattice)
    reached = grid.item_cells.reach_each(lattice, radius, grid.surface, skin_only=True)
    for placement, keys, reached_keys in zip(lattice, occupied, reached):
        expected = sampled_cells(grid, placement)
        assert as_cells(keys) == expected
        assert as_cells(reached_keys) == expanded(skin(expected), grid.pitch, radius) & surface


@pytest.mark.skipif("fork" not in multiprocessing.get_all_start_methods(), reason="workers need fork")
def test_workers_sample_the_same_cells(grid, placements):
    # Off-center placements don't share patterns, so they are the ones sent to workers.
    off_center = [Placement(p.item, p.center + 0.37 * grid.pitch, p.rotation, p.scale) for p in placements]
    serial = [as_cells(keys) for keys in grid.item_cells.occupied_by_each(off_center)]
    fresh_grid = VoxelGrid(grid.indices, grid.pitch, grid.origin, grid.config)
    with Execution(workers=2):
        parallel = [as_cells(keys) for keys in fresh_grid.item_cells.occupied_by_each(off_center)]
        skins = [as_cells(keys) for keys in fresh_grid.item_cells.skins_of_each(off_center)]
    assert parallel == serial
    assert skins == [skin(cells) for cells in serial]
