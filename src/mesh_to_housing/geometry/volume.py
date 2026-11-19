from dataclasses import dataclass, field
from functools import cached_property, lru_cache
from math import ceil
from weakref import WeakKeyDictionary

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
        self._solids = WeakKeyDictionary()

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
    cells = grid._solids.get(placement)
    if cells is None:
        cells = grid._solids[placement] = _sample_solid(grid, placement)
    return cells


def _world_bounds(placement):
    corners = np.array(np.meshgrid(*placement.item.bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    return corners.min(axis=0), corners.max(axis=0)


def _inside_item(points, placement):
    return placement.item.contains(((points - placement.center) @ placement.rotation) / placement.scale)


def _sample_solid(grid, placement):
    world_low, world_high = _world_bounds(placement)
    low = np.ceil((world_low - grid.origin) / grid.pitch - 1e-9).astype(int)
    high = np.floor((world_high - grid.origin) / grid.pitch + 1e-9).astype(int)
    lengths = high - low + 1
    if np.any(lengths <= 0):
        return frozenset()
    if np.prod(lengths.astype(float)) > grid.config.max_cells:
        raise ValueError("Item grid is too large; increase voxel_pitch or max_cells")
    indices = np.indices(tuple(lengths)).reshape(3, -1).T + low
    inside = _inside_item(grid.origin + indices * grid.pitch, placement)
    return frozenset(map(tuple, indices[inside].tolist()))



def outer_surfaces(grid, construction):
    """The target's surface and the construction's outer surface, as boolean masks on one shared frame."""
    from scipy.ndimage import binary_erosion, binary_fill_holes

    target_surface, target_low = grid.surface_mask
    cells = np.array(list(set().union(*(occupied_cells(grid, placement) for placement in construction))),
                     dtype=int).reshape(-1, 3)
    bounds = np.vstack((target_low, target_low + target_surface.shape - 1, cells))
    low = bounds.min(axis=0)
    shape = bounds.max(axis=0) - low + 1

    target = np.zeros(shape, dtype=bool)
    start = target_low - low
    target[tuple(slice(first, first + size) for first, size in zip(start, target_surface.shape))] = target_surface
    solid = np.zeros(shape, dtype=bool)
    solid[tuple((cells - low).T)] = True
    solid = binary_fill_holes(solid)
    return target, solid & ~binary_erosion(solid)
