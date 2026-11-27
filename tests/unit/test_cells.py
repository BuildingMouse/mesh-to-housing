import numpy as np

from mesh_to_housing.geometry.cells import CellBox, CellHolders, cell_indices, cell_keys, key_offsets
from mesh_to_housing.geometry.morphology import dilate_each

from ..reference import as_cells, expanded

CELLS = np.array([[-4000, 9, -11], [-4000, 9, 12], [0, -1, 0], [0, 0, 0], [4000, 500, 3]])


def test_keys_round_trip_and_sort_like_cells():
    keys = cell_keys(CELLS)
    np.testing.assert_array_equal(cell_indices(keys), CELLS)
    assert np.all(np.diff(keys) > 0)


def test_adding_an_offset_key_shifts_cells():
    offset = np.array([7, -3, 250])
    np.testing.assert_array_equal(cell_keys(CELLS) + key_offsets(offset), cell_keys(CELLS + offset))


def test_padded_boxes_grow_on_every_side_and_clip_cells_onto_their_edge():
    box = CellBox(np.array((2, -1, 0)), np.array((4, 1, 0))).padded(1)
    np.testing.assert_array_equal(box.low, (1, -2, -1))
    np.testing.assert_array_equal(box.shape, (5, 5, 3))
    cells = np.array([(1, -2, -1), (3, 0, 0), (9, -9, 0)])
    np.testing.assert_array_equal(np.stack(box.clipped(cells), axis=1), [(0, 0, 0), (2, 2, 1), (4, 0, 1)])


def test_cell_holders_count_the_keys_each_candidate_holds_across_chunks():
    rng = np.random.default_rng(3)
    lists = [np.unique(cell_keys(rng.integers(-5, 5, (int(size), 3)))) for size in rng.integers(0, 30, 23)]
    holders = CellHolders(lists, len(lists), keys_per_chunk=40)
    asked = np.unique(cell_keys(rng.integers(-6, 6, (200, 3))))
    np.testing.assert_array_equal(holders.lengths, [len(keys) for keys in lists])
    np.testing.assert_array_equal(holders.counts(asked), [np.isin(keys, asked).sum() for keys in lists])


def test_cell_holders_sum_the_weights_of_the_cells_they_hold():
    rng = np.random.default_rng(4)
    lists = [np.unique(cell_keys(rng.integers(-5, 5, (int(size), 3)))) for size in rng.integers(0, 30, 23)]
    holders = CellHolders(lists, len(lists), keys_per_chunk=40)
    asked = np.unique(cell_keys(rng.integers(-6, 6, (200, 3))))

    def weigh(keys):
        return 0.5 + (keys % 7) * 0.4

    np.testing.assert_allclose(holders.counts(asked, weigh),
                               [weigh(np.intersect1d(keys, asked)).sum() for keys in lists])
    np.testing.assert_allclose(holders.totals(weigh), [weigh(keys).sum() for keys in lists])
    np.testing.assert_array_equal(holders.totals(), [len(keys) for keys in lists])


def test_cell_holders_of_no_cells_count_nothing():
    holders = CellHolders([np.zeros(0, dtype=np.int64)] * 3, 3)
    np.testing.assert_array_equal(holders.counts(cell_keys(CELLS)), [0, 0, 0])


def test_dilation_reaches_every_cell_within_the_radius():
    rng = np.random.default_rng(5)
    lists = [np.unique(cell_keys(rng.integers(-4, 4, (int(size), 3)))) for size in rng.integers(1, 20, 12)]
    for keys, grown in zip(lists, dilate_each(lists, 1.0, 1.5)):
        assert np.all(np.diff(grown) > 0)
        assert as_cells(grown) == expanded(as_cells(keys), 1.0, 1.5)
