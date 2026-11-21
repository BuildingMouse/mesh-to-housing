from dataclasses import dataclass, field
from functools import cached_property, lru_cache
from math import ceil

import numpy as np

from .config import VoxelGridConfig


@dataclass(eq=False)
class VoxelGrid:
    """Occupied cells on a fixed grid; origin is the center of cell (0, 0, 0)."""

    indices: np.ndarray
    pitch: float
    origin: np.ndarray
    config: VoxelGridConfig = field(default_factory=VoxelGridConfig)

    def __post_init__(self):
        if not len(self.indices):
            raise ValueError("Mesh has no resolved volume; reduce voxel_pitch or increase gap_closing")
        self.origin = np.array(self.origin, dtype=float, copy=True)
        self.indices = np.array(self.indices, dtype=int, copy=True)
        self.cells = frozenset(map(tuple, self.indices.tolist()))

    @classmethod
    def from_mesh(cls, mesh, config=None):
        return _voxelize(mesh, VoxelGridConfig() if config is None else config)

    @property
    def points(self):
        return self.origin + self.indices * self.pitch

    @cached_property
    def surface_mask(self):
        """The surface cells as a boolean array, and the index of its first cell."""
        from scipy.ndimage import binary_erosion

        low = self.indices.min(axis=0)
        solid = np.zeros(self.indices.max(axis=0) - low + 1, dtype=bool)
        solid[tuple((self.indices - low).T)] = True
        return solid & ~binary_erosion(solid), low

    @cached_property
    def surface_cells(self):
        """Occupied cells with at least one face exposed to empty space."""
        mask, low = self.surface_mask
        return frozenset(map(tuple, (np.argwhere(mask) + low).tolist()))

    @cached_property
    def surface(self):
        from .surface import TargetSurface

        return TargetSurface(self)

    @cached_property
    def item_cells(self):
        from .item_cells import ItemCells

        return ItemCells(self)

    def outside_distance(self, cells):
        cells = np.asarray(cells, dtype=int).reshape(-1, 3)
        return self._target_tree.query(cells)[0] * self.pitch

    @cached_property
    def _target_tree(self):
        from scipy.spatial import cKDTree

        return cKDTree(self.indices)


def _cell_blocks(fine, samples):
    cells = np.array(fine.shape) // samples
    return fine[:cells[0] * samples, :cells[1] * samples, :cells[2] * samples].reshape(
        cells[0], samples, cells[1], samples, cells[2], samples)


@lru_cache(maxsize=8)
def _voxelize(mesh, config):
    from scipy.ndimage import binary_closing, binary_fill_holes, maximum_filter, minimum_filter

    samples = config.target_samples
    fine_pitch = config.pitch_for(mesh) / samples
    closing = ceil(config.gap_closing / (2 * fine_pitch))
    padding = closing + samples
    if np.prod(np.ceil(mesh.extents / fine_pitch) + 2 * padding + 5) > config.max_cells:
        raise ValueError("Voxel grid is too large; increase voxel_pitch or max_cells")
    voxels = mesh.voxelized(fine_pitch)
    surface = np.pad(voxels.matrix, padding)
    if closing:
        surface = binary_closing(surface, iterations=closing)
    solid = binary_fill_holes(surface)

    # A surface voxel straddles the mesh, so it counts as half filled. Without this the target grows with the pitch.
    fill = 2 * solid.astype(np.uint8) - surface.astype(np.uint8)
    half_filled = _cell_blocks(fill, samples).sum(axis=(1, 3, 5)) >= samples ** 3
    thick = maximum_filter(minimum_filter(solid, size=2 * samples + 1), size=2 * samples + 1)
    thin_amount = _cell_blocks(solid, samples).sum(axis=(1, 3, 5)) * ~_cell_blocks(thick, samples).any(axis=(1, 3, 5))
    holds_thin_part = (thin_amount > 0) & (2 * thin_amount >= maximum_filter(thin_amount, size=3))
    indices = np.argwhere(half_filled | holds_thin_part)
    origin = voxels.transform[:3, 3] + ((samples - 1) / 2 - padding) * fine_pitch
    return VoxelGrid(indices, fine_pitch * samples, origin, config)


def occupied_cells(grid, placement):
    """Cells whose centers lie inside the item, which measures its volume without bias at any pitch."""
    return grid.item_cells.occupied(placement)
