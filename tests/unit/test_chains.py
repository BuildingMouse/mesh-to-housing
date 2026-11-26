"""Chains of items laid end to end."""
from dataclasses import replace

import numpy as np
import pytest
import trimesh
from scipy.spatial.transform import Rotation

from mesh_to_housing import Link, MeshItem
from mesh_to_housing.fitting import ChainGroup

from ..chains import COLUMN, LINK, straight_chain
from ..meshes import dome_mesh, flat_top_mesh, l_mesh, table_mesh

MESHES = {
    "cylinder": trimesh.creation.cylinder(radius=0.15, height=1.0, sections=32),
    "ring": trimesh.creation.annulus(r_min=0.3, r_max=0.45, height=0.1),
    "L shape": l_mesh(),
    "dome": dome_mesh(),
    "table": table_mesh(),
    "flat top": flat_top_mesh(),
}


@pytest.mark.parametrize("name", MESHES)
def test_every_pose_lays_meshes_of_any_shape_exactly_along_their_span(name):
    mesh = MESHES[name]
    item = MeshItem(name.replace(" ", "_"), mesh)
    for pose in item.shape.poses:
        for anchor in ("middle", "outer"):
            link = Link(item, pose, anchor, overlap=0.1, max_bend=30.0, max_overlap=0.35)
            placement = link.placed(np.zeros(3), np.array((1.0, 0.0, 0.0)), np.array((0.0, 0.0, 1.0)),
                                    1.0 / pose.length)
            points = placement.world_points(mesh.vertices)
            np.testing.assert_allclose((points[:, 0].min(), points[:, 0].max()), (0.0, 1.0), atol=1e-9)
            assert points[:, 1].min() + points[:, 1].max() == pytest.approx(0.0, abs=1e-9)
            if anchor == "middle":
                assert points[:, 2].min() + points[:, 2].max() == pytest.approx(0.0, abs=1e-9)
            else:
                assert points[:, 2].max() == pytest.approx(0.0, abs=1e-9)


def test_segments_lie_along_their_spans_and_overlap_at_the_joints():
    chain = straight_chain()
    for index, placement in enumerate(chain.placements):
        along = placement.rotation @ COLUMN.shape.axes[:, 0]
        assert abs(along[0]) == pytest.approx(1.0)
        np.testing.assert_allclose(placement.box_center, chain.joints[index:index + 2].mean(axis=0), atol=1e-12)
    assert np.all(chain.lengths > chain.spans)
    assert chain.is_whole()


def test_outer_segments_have_their_up_side_on_the_span():
    placement = straight_chain(link=replace(LINK, anchor="outer")).placements[0]
    assert placement.world_points(COLUMN.mesh.vertices)[:, 2].max() == pytest.approx(0.0, abs=1e-12)


def test_a_chain_is_broken_by_gaps_heavy_overlap_and_bends_past_its_link():
    chain = straight_chain()
    apart = chain.joints.copy()
    apart[2:] += (0.2, 0.0, 0.0)
    assert not chain.changed(joints=apart).is_whole()
    squeezed = chain.joints.copy()
    squeezed[2:] -= (0.3, 0.0, 0.0)
    assert not chain.changed(joints=squeezed).is_whole()
    bent = chain.joints.copy()
    bent[2:] = bent[1] + (bent[2:] - bent[1]) @ Rotation.from_euler("z", 40, degrees=True).as_matrix().T
    assert not chain.changed(joints=bent).is_whole()
    assert straight_chain(link=replace(LINK, max_bend=45.0)).changed(joints=bent).is_whole()


def test_changed_chains_keep_the_placements_of_segments_that_stay():
    chain = straight_chain()
    joints = chain.joints.copy()
    joints[3] += (0.0, 0.05, 0.0)
    moved = chain.changed(joints=joints)
    assert moved.placements[:2] == chain.placements[:2]
    assert moved.placements[2] is not chain.placements[2]
    assert chain.part(1, 3).placements == chain.placements[1:3]


def test_chains_grown_at_both_ends_keep_the_placements_between():
    chain = straight_chain()
    step = chain.joints[1] - chain.joints[0]
    joints = np.vstack((chain.joints[0] - step, chain.joints, chain.joints[-1] + step))
    grown = chain.changed(joints=joints, ups=np.tile((0.0, 0.0, 1.0), (5, 1)), scales=np.ones(5))
    assert grown.placements[1:4] == chain.placements
    assert grown.is_whole()


def test_relaid_chains_keep_their_middle_joint_and_fit_the_new_lengths():
    chain = straight_chain(count=4)
    relaid = chain.relaid(np.array([1.0, 1.2, 1.2, 1.0]))
    np.testing.assert_allclose(relaid.joints[2], chain.joints[2])
    np.testing.assert_allclose(relaid.spans, relaid.lengths * 0.9)


def test_chains_cant_be_changed_in_place():
    chain = straight_chain()
    with pytest.raises(ValueError):
        chain.joints[0] += 1.0


def test_a_plain_group_has_only_its_chain_and_cuts_it():
    chain = straight_chain()
    group = ChainGroup(chain)
    assert group.members == (chain,)
    assert group.part(1, 3).placements == chain.placements[1:3]
    assert group.copies_of(chain.placements[0]) == [chain.placements[0]]
