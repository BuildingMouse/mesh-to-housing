"""The flow through the target, and paths traced through its middle and over its surface."""
import numpy as np
import pytest
import trimesh

from mesh_to_housing.geometry.cells import cell_keys
from mesh_to_housing.geometry.paths import Path, medial_path, on_surface, surface_path
from mesh_to_housing.geometry.voxel_grid import VoxelGrid, VoxelGridConfig

GRID = VoxelGridConfig(resolution=40, target_samples=1)
BAR = VoxelGrid.from_mesh(trimesh.creation.box(extents=(4.0, 0.4, 0.4)), GRID)
BOX = VoxelGrid.from_mesh(trimesh.creation.box(extents=(3.0, 2.0, 1.0)), GRID)


def directions(path):
    steps = np.diff(path.points, axis=0)
    return steps / np.linalg.norm(steps, axis=1, keepdims=True)


def test_paths_are_measured_along_their_points_and_run_straight_on_past_their_ends():
    path = Path(np.array([(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 2.0, 0.0)]))
    assert path.length == pytest.approx(3.0)
    np.testing.assert_allclose(path.at([0.5, 2.0, 4.0, -1.0]), [(0.5, 0, 0), (1, 1, 0), (1, 3, 0), (-1, 0, 0)])
    np.testing.assert_allclose(path.reversed().at(0.0), [(1.0, 2.0, 0.0)])


def test_the_flow_runs_along_a_bar():
    points = np.column_stack((np.linspace(-1.5, 1.5, 7), np.zeros(7), np.zeros(7)))
    np.testing.assert_allclose(np.abs(BAR.flow.direction_at(points)[:, 0]), 1.0, atol=1e-6)


def test_the_flow_runs_along_a_thin_leg_and_along_the_flat_body_it_hangs_from():
    # The body's medial axis is a sheet, and the leg is two cells thick.
    body = trimesh.creation.box(extents=(4.0, 2.4, 1.2))
    leg = trimesh.creation.box(extents=(0.2, 0.2, 2.0))
    leg.apply_translation((1.0, 0.0, -1.55))
    grid = VoxelGrid.from_mesh(trimesh.util.concatenate([body, leg]), GRID)
    leg_points = np.column_stack((np.full(5, 1.0), np.zeros(5), np.linspace(-2.2, -1.0, 5)))
    body_points = np.column_stack((np.linspace(-1.15, 0.2, 4), np.zeros(4), np.zeros(4)))
    assert np.all(np.abs(grid.flow.direction_at(leg_points)[:, 2]) > 0.95)
    assert np.all(np.abs(grid.flow.direction_at(body_points)[:, 0]) > 0.95)


def test_medial_paths_run_along_the_middle_of_a_bar_to_its_ends():
    path, seed = medial_path(BAR, np.array((0.3, 0.0, 0.0)), 3.0)
    np.testing.assert_allclose(path.at(seed), [(0.3, 0.0, 0.0)], atol=1e-9)
    np.testing.assert_allclose(path.points[[0, -1], 0], (-2.0, 2.0), atol=BAR.pitch)
    assert np.all(np.abs(directions(path)[:, 0]) > 0.99)
    assert np.all(BAR.in_target(cell_keys(BAR.indices_of(path.points))))


def test_surface_paths_follow_the_grain_and_stop_at_edges():
    cylinder = VoxelGrid.from_mesh(trimesh.creation.cylinder(radius=0.5, height=3.0, sections=64), GRID)
    path, _ = surface_path(cylinder, np.array((0.6, 0.0, 0.2)), None, 3.0, 45.0)
    assert np.all(np.abs(directions(path)[:, 2]) > 0.95)
    assert np.all(np.abs(path.points[:, 2]) < 1.5)
    assert path.length > 2.5


def test_surface_paths_may_bend_along_their_length_but_not_roll_sideways():
    cylinder = VoxelGrid.from_mesh(trimesh.creation.cylinder(radius=0.5, height=3.0, sections=64), GRID)

    def turned_around_the_axis(slant):
        heading = np.array((0.0, np.sin(np.radians(slant)), np.cos(np.radians(slant))))
        path, _ = surface_path(cylinder, np.array((0.6, 0.0, 0.0)), heading, 3.0, 45.0)
        return np.degrees(np.abs(np.arctan2(path.normals[:, 1], path.normals[:, 0]))).max()

    assert turned_around_the_axis(0) < 1.0
    assert turned_around_the_axis(60) < 90.0
    assert turned_around_the_axis(90) > 170.0


def test_a_flat_face_has_no_grain():
    points = np.column_stack((np.linspace(-0.6, 0.6, 5), np.full(5, 0.1), np.full(5, 0.5)))
    _, has_grain = BOX.surface.grain_at(points, np.tile((0.0, 0.0, 1.0), (5, 1)))
    assert not has_grain.any()


@pytest.mark.parametrize("heading", [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), None])
def test_surface_paths_run_straight_over_a_flat_face_to_its_edges(heading):
    start = np.array((0.2, 0.1, 0.6))
    heading = None if heading is None else np.array(heading)
    path, _ = surface_path(BOX, start, heading, 3.0, 45.0)
    across = 1 if heading is None or heading[0] else 0
    np.testing.assert_allclose(path.points[:, across], start[across], atol=1e-3)
    assert np.all(np.abs(path.points[:, 2] - 0.5) < BOX.pitch)
    assert path.length > (2.8 if across else 1.8)


def test_points_go_onto_the_surface_a_quarter_cell_out_from_the_surface_cells():
    point, normal = on_surface(BOX, np.array((0.3, 0.2, 0.9)))
    top = BOX.points_of(BOX.surface.indices)[:, 2].max()
    np.testing.assert_allclose(normal, (0.0, 0.0, 1.0), atol=1e-9)
    np.testing.assert_allclose(point, (0.3, 0.2, top + BOX.pitch / 4), atol=1e-9)
