import numpy as np

from mesh_to_housing.geometry.cells import cell_indices, cell_keys, key_offsets

CELLS = np.array([[-4000, 9, -11], [-4000, 9, 12], [0, -1, 0], [0, 0, 0], [4000, 500, 3]])


def test_keys_round_trip_and_sort_like_cells():
    keys = cell_keys(CELLS)
    np.testing.assert_array_equal(cell_indices(keys), CELLS)
    assert np.all(np.diff(keys) > 0)


def test_adding_an_offset_key_shifts_cells():
    offset = np.array([7, -3, 250])
    np.testing.assert_array_equal(cell_keys(CELLS) + key_offsets(offset), cell_keys(CELLS + offset))
