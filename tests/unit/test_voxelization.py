import numpy as np
import pytest
import trimesh

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
