from dataclasses import dataclass, field
from functools import cached_property
from typing import Optional

import numpy as np
import trimesh

from ..utils.config import Config
from ..utils.values import NonNegativeFloat, PositiveFloat, PositiveInt
from .cells import CellBox, CellKeys, cell_indices, cell_keys


class VoxelGridConfig(Config):
    """Lengths are in target units, so they keep their meaning at any pitch."""

    voxel_pitch: Optional[PositiveFloat] = None
    resolution: PositiveInt = 96
    gap_closing: NonNegativeFloat = 0.0
    target_samples: PositiveInt = 3
    max_cells: PositiveInt = 100_000_000

    def pitch_for(self, mesh):
        return float(mesh.extents.max() / self.resolution if self.voxel_pitch is None else self.voxel_pitch)


@dataclass(eq=False)
class VoxelGrid:
    """The target as cells on a fixed grid, and everything measured from them."""

    indices: np.ndarray
    pitch: float
    origin: np.ndarray
    config: VoxelGridConfig = field(default_factory=VoxelGridConfig)

    def __post_init__(self):
        if not len(self.indices):
            raise ValueError("Mesh has no resolved volume; reduce voxel_pitch or increase gap_closing")
        self.origin = np.array(self.origin, dtype=float, copy=True)
        self.indices = np.array(self.indices, dtype=int, copy=True)

    @classmethod
    def from_mesh(cls, mesh: trimesh.Trimesh, config: Optional[VoxelGridConfig] = None) -> "VoxelGrid":
        """The grid for a mesh. Grids are cached, so the same mesh and config give back the same grid object."""
        from .voxelization import voxelize

        return voxelize(mesh, VoxelGridConfig() if config is None else config)

    def points_of(self, indices: np.ndarray) -> np.ndarray:
        """The centers of cells given by index."""
        return self.origin + indices * self.pitch

    @cached_property
    def keys(self) -> CellKeys:
        return np.sort(cell_keys(self.indices))

    @cached_property
    def box(self) -> CellBox:
        return CellBox(self.indices.min(axis=0), self.indices.max(axis=0))

    @cached_property
    def solid_mask(self) -> np.ndarray:
        """The target cells as a boolean array over the box."""
        solid = np.zeros(self.box.shape, dtype=bool)
        solid[tuple((self.indices - self.box.low).T)] = True
        return solid

    def in_target(self, keys: CellKeys) -> np.ndarray:
        return self.box.lookup(self.solid_mask, keys)

    def outside_distance(self, keys: CellKeys) -> np.ndarray:
        """How far each cell is from the nearest target cell, in target units. Target cells are at 0."""
        squared_in_box, box = self._outside_field
        numbers = box.numbers(keys)
        distances = np.empty(len(numbers))
        inside = numbers >= 0
        distances[inside] = np.sqrt(squared_in_box.ravel()[numbers[inside]]) * self.pitch
        if not inside.all():
            distances[~inside] = self._target_tree.query(cell_indices(keys[~inside]))[0] * self.pitch
        return distances

    def outward_normals(self, indices: np.ndarray) -> np.ndarray:
        """Outward unit normals at the given target cells"""
        from scipy.ndimage import gaussian_filter

        low = self.indices.min(axis=0) - 2
        solid = np.zeros(self.indices.max(axis=0) - low + 3)
        solid[tuple((self.indices - low).T)] = 1.0
        blurred = gaussian_filter(solid, sigma=1.0)
        del solid
        local = np.asarray(indices, dtype=int).reshape(-1, 3) - low
        # The central differences np.gradient takes, only at these cells; the padding keeps them off the edges.
        normals = -np.stack([(blurred[tuple((local + step).T)] - blurred[tuple((local - step).T)]) / 2.0
                             for step in np.eye(3, dtype=int)], axis=1)
        lengths = np.linalg.norm(normals, axis=1, keepdims=True)
        return np.where(lengths > 0, normals / np.where(lengths > 0, lengths, 1), (0.0, 0.0, 1.0))

    @cached_property
    def surface(self) -> "TargetSurface":
        from .surface import TargetSurface

        return TargetSurface(self)

    @cached_property
    def item_cells(self) -> "ItemCells":
        from .item_cells import ItemCells

        return ItemCells(self)

    @cached_property
    def _outside_field(self) -> tuple[np.ndarray, CellBox]:
        """Squared distances, in cells, from each cell of a padded box to the nearest target cell.
        Squares of whole cell offsets are exact integers, so their square roots match a float distance transform.
        """
        from scipy.ndimage import distance_transform_edt

        padding = 32
        outside = ~np.pad(self.solid_mask, padding)
        nearest = distance_transform_edt(outside, return_distances=False, return_indices=True)
        del outside
        squared = np.zeros(nearest.shape[1:], dtype=np.int32)
        for axis, offsets in enumerate(nearest):
            shape = [1, 1, 1]
            shape[axis] = -1
            offsets -= np.arange(offsets.shape[axis], dtype=offsets.dtype).reshape(shape)
            offsets *= offsets
            squared += offsets
        low = self.box.low - padding
        return squared, CellBox(low, low + np.array(squared.shape) - 1)

    @cached_property
    def _target_tree(self):
        from scipy.spatial import cKDTree

        return cKDTree(self.indices)
