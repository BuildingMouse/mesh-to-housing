"""Item shapes: their own axes, the points that test whether they fit, and the poses chains can lay them in."""
import numpy as np
import pytest
import trimesh
from scipy.spatial.transform import Rotation

from mesh_to_housing import Cuboid, MeshItem

from ..meshes import dome_mesh, flat_top_mesh, l_mesh, table_mesh

PLANK = Cuboid("plank", (0.3, 2.0, 0.1))
BALL = MeshItem("ball", trimesh.creation.icosphere(subdivisions=3, radius=0.5))
CYLINDER = MeshItem("cylinder", trimesh.creation.cylinder(radius=0.15, height=1.0, sections=48))
MESHES = {"ring": trimesh.creation.annulus(r_min=0.3, r_max=0.45, height=0.1), "L shape": l_mesh(),
          "dome": dome_mesh(), "table": table_mesh(), "flat top": flat_top_mesh()}


def test_item_shape_orders_axes_from_longest_to_thinnest_as_a_proper_rotation():
    shape = PLANK.shape
    np.testing.assert_allclose(np.abs(shape.axes), np.eye(3)[:, [1, 0, 2]], atol=1e-9)
    assert np.linalg.det(shape.axes) == pytest.approx(1.0)
    np.testing.assert_allclose((shape.length, shape.width, shape.thickness), (2.0, 0.3, 0.1), atol=1e-9)


def test_item_shape_finds_the_axes_of_a_turned_mesh_away_from_its_origin():
    turn = Rotation.from_euler("xyz", (20, 35, 50), degrees=True).as_matrix()
    mesh = trimesh.creation.box(extents=(0.3, 2.0, 0.1))
    mesh.apply_transform(np.vstack((np.column_stack((turn, (0.4, -0.2, 0.1))), (0, 0, 0, 1))))
    shape = MeshItem("turned", mesh).shape
    np.testing.assert_allclose((shape.length, shape.width, shape.thickness), (2.0, 0.3, 0.1), atol=1e-6)
    np.testing.assert_allclose(np.abs(np.sum(shape.axes * turn[:, [1, 0, 2]], axis=0)), 1.0, atol=1e-6)


@pytest.mark.parametrize("name", MESHES)
def test_each_pose_lays_one_axis_along_the_chain_and_one_side_up(name):
    shape = MeshItem(name.replace(" ", "_"), MESHES[name]).shape
    sizes = np.array((shape.length, shape.width, shape.thickness))
    assert len(shape.poses) == 12 and len({pose.name for pose in shape.poses}) == 12
    for pose in shape.poses:
        assert np.linalg.det(pose.axes) == pytest.approx(1.0)
        # Each of the pose's directions is one of the item's own axes, so its sizes are the item's, reordered.
        assert np.allclose(np.abs(pose.axes.T @ shape.axes).max(axis=1), 1.0)
        assert sorted((pose.length, pose.width, pose.thickness)) == pytest.approx(sorted(sizes), abs=1e-9)
        np.testing.assert_allclose(pose.middle, shape.middle, atol=1e-9)
        assert pose.outer_middle @ pose.axes[:, 2] == pytest.approx(pose.high[2])


def test_boxes_meet_flush_and_lie_flat_every_way():
    for item in (Cuboid("cube", (1.0, 1.0, 1.0)), PLANK):
        assert item.shape.fill > 0.95
        for pose in item.shape.poses:
            assert pose.end_contact > 0.95 and pose.side_contact > 0.95


def test_a_plank_can_also_run_across_a_chain():
    across = PLANK.shape.pose("middle along, +thin up")
    assert across.length == pytest.approx(0.3) and across.end_contact > 0.95


def test_a_ball_meets_its_neighbors_only_at_points():
    assert all(pose.end_contact < 0.3 and pose.side_contact < 0.3 for pose in BALL.shape.poses)


def test_a_cylinder_meets_flush_only_along_its_axis():
    assert CYLINDER.shape.pose("long along, +middle up").end_contact > 0.7
    assert CYLINDER.shape.pose("middle along, +long up").end_contact < 0.5


def test_a_flat_side_over_an_uneven_underside_lies_flat_but_joins_badly():
    shape = MeshItem("flat_top", flat_top_mesh()).shape
    assert max(pose.side_contact for pose in shape.poses) > 0.95
    assert max(pose.end_contact for pose in shape.poses) < 0.6 and shape.fill < 0.4


def test_a_table_lies_flat_on_its_top_and_not_on_its_legs():
    shape = MeshItem("table", table_mesh()).shape
    up = {np.sign(pose.axes[2, 2]): pose.side_contact for pose in shape.poses if abs(pose.axes[2, 2]) > 0.99}
    assert up[1.0] > 0.95 and up[-1.0] < 0.3


def test_samples_reach_the_item_extremes():
    shape = CYLINDER.shape
    reach = shape.samples @ shape.axes
    np.testing.assert_allclose(reach.min(axis=0), shape.low, atol=1e-9)
    np.testing.assert_allclose(reach.max(axis=0), shape.high, atol=1e-9)
