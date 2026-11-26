"""Moves of whole chains."""
from dataclasses import replace

import numpy as np
import pytest
import trimesh
from scipy.spatial.transform import Rotation

from mesh_to_housing import ChainMoves, FittingTask, Nudges, TransformConstraints, VoxelGridConfig

from ..chains import COLUMN, LINK, straight_chain

GRID = VoxelGridConfig(resolution=40, target_samples=1)


def task_for(mesh):
    return FittingTask(mesh, (COLUMN,), 12, TransformConstraints(scale_bounds=(0.2, 2.0)))


def test_chain_moves_keep_chains_whole_and_within_the_scale_bounds():
    task = task_for(trimesh.creation.box(extents=(3.0, 0.3, 0.3)))
    moves = ChainMoves(grid=GRID, shift=1.0, turn=10.0, rescale=1.2).around(task, straight_chain(scale=0.5))
    assert {len(moved) for moved in moves} == {2, 3, 4}
    for moved in moves:
        assert moved.is_whole()
        assert np.all((0.2 <= moved.scales) & (moved.scales <= 2.0))


@pytest.mark.parametrize("max_bend, moves_keeping_the_bend", [(30.0, False), (40.0, True)])
def test_a_chain_moves_as_far_as_its_own_bend_limit_allows(max_bend, moves_keeping_the_bend):
    chain = straight_chain(scale=0.5, link=replace(LINK, max_bend=max_bend))
    joints = chain.joints.copy()
    joints[2:] = joints[1] + (joints[2:] - joints[1]) @ Rotation.from_euler("z", 35, degrees=True).as_matrix().T
    bent = chain.changed(joints=joints)
    moves = ChainMoves(grid=GRID).around(task_for(trimesh.creation.box(extents=(3.0, 2.0, 0.3))), bent)
    assert any(len(moved) == 3 and moved.bends().max() > 30 for moved in moves) == moves_keeping_the_bend


def test_a_new_end_keeps_the_other_segments_and_a_row_stays_on_the_surface():
    task = task_for(trimesh.creation.box(extents=(3.0, 2.0, 1.0)))
    row = straight_chain(scale=0.5, link=replace(LINK, anchor="outer"), height=0.5)
    ends = ChainMoves(grid=GRID, shift=0.0, turn=0.0, rescale=1.0).around(task, row)
    grown = [moved for moved in ends if len(moved) == len(row) + 1]
    assert len(grown) == 2
    for moved in grown:
        assert set(row.placements) <= set(moved.placements)
        assert np.all(np.abs(moved.joints[:, 2] - 0.5) < GRID.pitch_for(task.target))


@pytest.mark.parametrize("kind", [Nudges, ChainMoves])
def test_finer_moves_shrink_every_step_by_the_same_factor(kind):
    moves = kind(shift=2.0, turn=20.0, rescale=1.4)
    finer = moves.finer(0.5)
    assert (finer.shift, finer.turn, finer.rescale) == pytest.approx((1.0, 10.0, 1.2))
    assert type(finer) is type(moves)
