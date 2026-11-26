"""Chains proposed along the middle of the target's parts and over its surface."""
import numpy as np
import pytest
import trimesh

from mesh_to_housing import (
    CandidateSettings, Fill, FittingPipeline, FittingTask, MedialChains, MeshItem, Stage, SurfaceChains,
    TransformConstraints, UncoveredSurfaceConfig, VoxelGridConfig,
)
from mesh_to_housing.geometry.rotations import side_and_up
from mesh_to_housing.geometry.voxel_grid import VoxelGrid

from ..chains import COLUMN
from ..meshes import table_mesh, taper_mesh
from ..reference import sampled_cells

BALL = MeshItem("ball", trimesh.creation.icosphere(subdivisions=3, radius=0.5))
CYLINDER = MeshItem("cylinder", trimesh.creation.cylinder(radius=0.15, height=1.0, sections=48))
TABLE = MeshItem("table", table_mesh())
GRID = VoxelGridConfig(resolution=40, target_samples=1)


def task_for(mesh, item=COLUMN):
    return FittingTask(mesh, (item,), 10, TransformConstraints(scale_bounds=(0.2, 2.0)))


@pytest.mark.parametrize("path_grid", [None, VoxelGridConfig(resolution=80, target_samples=1)])
def test_medial_chains_run_along_a_bar_and_stay_inside_it(path_grid):
    task = task_for(trimesh.creation.box(extents=(4.0, 0.4, 0.4)))
    grid = VoxelGrid.from_mesh(task.target, GRID)
    chains = MedialChains(grid=GRID, path_grid=path_grid, chains=4, fit=1.0).propose_chains(
        task, [], np.random.default_rng(1))
    lengthwise = [chain for chain in chains if chain.link.pose.length == pytest.approx(COLUMN.shape.length)]
    longest = max(lengthwise, key=len)
    assert len(longest) >= 3
    assert np.all(np.abs(longest.directions[:, 0]) > 0.95)
    for placement in longest.placements:
        assert sampled_cells(grid, placement) <= frozenset(map(tuple, grid.indices))


def test_surface_chains_lie_flat_on_the_surface():
    task = task_for(trimesh.creation.box(extents=(3.0, 2.0, 1.0)))
    chains = SurfaceChains(grid=GRID, chains=6, beside=0).propose_chains(task, [], np.random.default_rng(2))
    assert chains
    facing = []
    for chain in chains:
        assert chain.link.anchor == "outer"
        for placement, up, along in zip(chain.placements, chain.ups, chain.directions):
            face = placement.rotation @ chain.link.pose.axes[:, 2]
            np.testing.assert_allclose(np.abs(face @ side_and_up(along, up)[1]), 1.0, atol=1e-9)
            facing.append(np.max(np.abs(face)))
    # On a box, rows lie flat on its faces. Normals tilt a little within a few cells of an edge.
    assert np.mean(np.array(facing) > np.cos(np.radians(15))) > 0.8


def test_segments_grown_either_way_from_the_seed_face_the_way_the_chain_runs():
    task = task_for(trimesh.creation.box(extents=(6.0, 0.6, 0.6)), MeshItem("taper", taper_mesh()))
    chains = MedialChains(grid=VoxelGridConfig(resolution=60, target_samples=1), chains=3, fit=0.8).propose_chains(
        task, [], np.random.default_rng(0))
    assert any(len(chain) > 1 for chain in chains)
    for chain in chains:
        for index, placement in enumerate(chain.placements):
            own = chain.link.placed(chain.joints[index], chain.joints[index + 1], chain.ups[index], chain.scales[index])
            np.testing.assert_allclose(placement.rotation, own.rotation, atol=1e-12)
            np.testing.assert_allclose(placement.center, own.center, atol=1e-12)


def test_chain_sources_offer_their_segments_as_plain_proposals():
    task = task_for(trimesh.creation.box(extents=(4.0, 0.4, 0.4)))
    source = MedialChains(grid=GRID, chains=2)
    chains = source.propose_chains(task, [], np.random.default_rng(3))
    segments = source.propose(task, [], np.random.default_rng(3))
    assert len(segments) == sum(len(chain) for chain in chains)


def test_poses_have_their_thinnest_side_up_and_one_stands_for_those_that_measure_the_same():
    poses = MedialChains().poses(COLUMN)
    assert [pose.name for pose in poses] == ["long along, +thin up", "middle along, +thin up"]


def test_medial_chains_leave_out_items_whose_ends_dont_meet_flush():
    medial = MedialChains()
    assert medial.poses(BALL) == []
    assert [pose.length for pose in medial.poses(CYLINDER)] == [pytest.approx(1.0)]


def test_surface_rows_lay_items_on_a_flat_or_round_side():
    surface = SurfaceChains()
    assert surface.poses(BALL) == []
    assert surface.poses(CYLINDER)
    table = surface.poses(TABLE)
    assert table and all(pose.side_contact > 0.95 for pose in table)


def test_chain_sources_survive_a_trip_through_yaml():
    pipeline = FittingPipeline(
        losses={"fit": UncoveredSurfaceConfig(grid=GRID)},
        proposals={"medial": MedialChains(grid=GRID, min_end_contact=0.7),
                   "surface": SurfaceChains(grid=GRID, path_grid=VoxelGridConfig(resolution=80), beside=2)},
        steps=(Stage(minimize="fit", candidates=CandidateSettings(refreshed=("medial", "surface")),
                     steps=(Fill(),)),),
    )
    assert FittingPipeline.from_yaml(pipeline.to_yaml()) == pipeline
