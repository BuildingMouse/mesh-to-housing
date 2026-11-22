import numpy as np
import trimesh

from mesh_to_housing import Cuboid, FittingTask, Placement, Swaps


def two_item_task():
    catalog = (Cuboid("tile", (0.6, 0.6, 0.15)), Cuboid("column", (0.15, 0.15, 0.6)))
    return FittingTask(trimesh.creation.box(extents=(1.0, 1.5, 1.0)), catalog, 4)


def test_swaps_offer_the_other_items_in_the_same_spot():
    task = two_item_task()
    tile, column = task.catalog
    placement = Placement(tile, (0.1, 0.2, 0.0), np.eye(3), 1.0)
    (swapped,) = Swaps().around(task, placement)
    assert swapped.item is column and swapped.scale == placement.scale
    np.testing.assert_allclose(swapped.box_center, placement.box_center)
    np.testing.assert_allclose(swapped.rotation, placement.rotation)
