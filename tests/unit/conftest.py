import numpy as np
import pytest
import trimesh
from scipy.spatial.transform import Rotation

from mesh_to_housing import Cuboid, FittingTask, Placement, TransformConstraints, VoxelGridConfig
from mesh_to_housing.geometry.voxel_grid import VoxelGrid


@pytest.fixture
def task():
    return FittingTask(trimesh.creation.box(extents=(1.0, 1.5, 1.0)), (Cuboid("tile", (0.6, 0.6, 0.15)),), 5,
                       TransformConstraints(scale_bounds=(0.2, 2.0)))


@pytest.fixture
def grid_config():
    return VoxelGridConfig(resolution=12, target_samples=1)


@pytest.fixture
def grid(task, grid_config):
    return VoxelGrid.from_mesh(task.target, grid_config)


@pytest.fixture
def placements(task, grid):
    """Placements on and off cell centers, turned and not, at two scales, plus one partly and one wholly
    outside the target.
    """
    item = task.catalog[0]
    rotations = (np.eye(3), Rotation.from_euler("xyz", (15, 35, 10), degrees=True).as_matrix())
    placements = [Placement(item, grid.origin + np.array(offset) * grid.pitch, rotation, scale)
                  for offset in ((2, 3, 2), (3, 3, 2), (0.3, 1.2, 0.4))
                  for rotation in rotations for scale in (0.5, 1.0)]
    placements.append(Placement(item, grid.origin, np.eye(3), 2.0))
    placements.append(Placement(item, grid.origin + 30 * grid.pitch, np.eye(3)))
    return placements
