import numpy as np
import pytest
import trimesh

from mesh_to_housing.geometry.cells import cell_keys
from mesh_to_housing.geometry.voxelization import _surface_voxels


@pytest.mark.parametrize("mesh", [trimesh.creation.icosphere(subdivisions=2, radius=1.3),
                                  trimesh.creation.box(extents=(1.0, 2.5, 0.4)),
                                  trimesh.creation.torus(1.0, 0.3)], ids=["sphere", "box", "torus"])
def test_surface_voxels_in_batches_match_trimesh(mesh):
    pitch = 0.07
    expected = mesh.voxelized(pitch)
    shell, corner = _surface_voxels(mesh, pitch, triangles_per_batch=64)
    np.testing.assert_array_equal(shell, expected.matrix)
    np.testing.assert_array_equal(corner, expected.transform[:3, 3])


def test_outside_distance_matches_the_nearest_target_cell(grid):
    rng = np.random.default_rng(2)
    cells = rng.integers(grid.box.low - 45, grid.box.low + grid.box.shape + 45, (500, 3))
    nearest = np.linalg.norm(cells[:, None, :] - grid.indices[None, :, :], axis=2).min(axis=1)
    np.testing.assert_allclose(grid.outside_distance(cell_keys(cells)), nearest * grid.pitch, rtol=0, atol=1e-12)
