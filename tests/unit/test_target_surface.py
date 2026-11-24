"""Thickness and roughness of the target surface."""
import numpy as np
import pytest
import trimesh

from mesh_to_housing import VoxelGridConfig
from mesh_to_housing.geometry.voxel_grid import VoxelGrid

PITCH = 0.125


@pytest.fixture
def slab():
    """A 4 * 4 slab one unit thick, eight cells across its thickness."""
    return VoxelGrid.from_mesh(trimesh.creation.box(extents=(4.0, 4.0, 1.0)), VoxelGridConfig(voxel_pitch=PITCH))


def face_middle(grid):
    """Surface cells in the middle of the top and bottom faces, away from every edge."""
    points = grid.points_of(grid.surface.indices)
    return (np.abs(points[:, :2]) < 1.0).all(axis=1)


def test_thickness_measures_across_parts_narrower_than_two_radii(slab):
    middle = face_middle(slab)
    np.testing.assert_allclose(slab.surface.thickness(1.0)[middle], 1.0, atol=PITCH)
    # With a smaller radius the slab reads as about two radii thick.
    assert slab.surface.thickness(0.25)[middle].max() <= 2 * 0.25 + 2 * PITCH
    assert slab.surface.thickness(0.25)[middle].max() < slab.surface.thickness(1.0)[middle].min()


def test_roughness_is_zero_on_flat_faces_and_higher_at_edges(slab):
    roughness = slab.surface.roughness(2 * PITCH)
    assert roughness[face_middle(slab)].max() < 1e-6
    points = slab.points_of(slab.surface.indices)
    corners = (np.abs(points[:, :2]) > 1.85).all(axis=1)
    assert roughness[corners].min() > 0.15
    assert ((0 <= roughness) & (roughness <= 1)).all()


@pytest.mark.parametrize("cells_thick", [2, 3])
def test_thin_flat_parts_are_not_rough(cells_thick):
    plate = VoxelGrid.from_mesh(trimesh.creation.box(extents=(4.0, 4.0, cells_thick * PITCH)),
                                VoxelGridConfig(voxel_pitch=PITCH))
    assert plate.surface.roughness(2 * PITCH)[face_middle(plate)].max() < 1e-6


def test_measures_are_cached_and_read_only(slab):
    for measure in (slab.surface.thickness, slab.surface.roughness):
        values = measure(0.25)
        assert measure(0.25) is values
        with pytest.raises(ValueError):
            values[0] = 0.0
