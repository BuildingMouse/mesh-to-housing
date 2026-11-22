from dataclasses import dataclass, field
from functools import cached_property
from typing import Optional

import numpy as np
import trimesh

from ..utils.values import positive_integer
from .cells import CellBox, CellKeys, cell_indices, cell_keys


@dataclass(frozen=True)
class VoxelGridConfig:
    """Lengths are in target units, so they keep their meaning at any pitch."""

    voxel_pitch: float = None
    resolution: int = 96
    gap_closing: float = 0.0
    target_samples: int = 3
    max_cells: int = 100_000_000

    def __post_init__(self):
        if self.voxel_pitch is not None and (not np.isfinite(self.voxel_pitch) or self.voxel_pitch <= 0):
            raise ValueError("voxel_pitch must be finite and positive")
        if not np.isfinite(self.gap_closing) or self.gap_closing < 0:
            raise ValueError("gap_closing must be finite and nonnegative")
        for name in ("resolution", "target_samples", "max_cells"):
            positive_integer(getattr(self, name), name)

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
        distances_in_box, box = self._outside_field
        numbers = box.numbers(keys)
        distances = np.empty(len(numbers))
        inside = numbers >= 0
        distances[inside] = distances_in_box.ravel()[numbers[inside]]
        if not inside.all():
            distances[~inside] = self._target_tree.query(cell_indices(keys[~inside]))[0] * self.pitch
        return distances

    def outward_normals(self, indices: np.ndarray) -> np.ndarray:
        """Outward unit normals at the given cells, from the gradient of a slightly blurred copy of the solid."""
        gradient, low = self._solid_gradient
        local = tuple((np.asarray(indices, dtype=int).reshape(-1, 3) - low).T)
        normals = -np.stack([component[local] for component in gradient], axis=1)
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
        from scipy.ndimage import distance_transform_edt

        padding = 32
        solid = np.pad(self.solid_mask, padding)
        low = self.box.low - padding
        return distance_transform_edt(~solid) * self.pitch, CellBox(low, low + np.array(solid.shape) - 1)

    @cached_property
    def _target_tree(self):
        from scipy.spatial import cKDTree

        return cKDTree(self.indices)

    @cached_property
    def _solid_gradient(self) -> tuple[list[np.ndarray], np.ndarray]:
        from scipy.ndimage import gaussian_filter

        low = self.indices.min(axis=0) - 2
        solid = np.zeros(self.indices.max(axis=0) - low + 3)
        solid[tuple((self.indices - low).T)] = 1.0
        return np.gradient(gaussian_filter(solid, sigma=1.0)), low
