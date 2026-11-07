from dataclasses import dataclass
from numbers import Integral

import numpy as np

from ..items.cuboid import Cuboid


@dataclass
class VoxelGrid:
    """Occupied cells on a fixed grid; origin is the center of cell (0, 0, 0)."""

    indices: np.ndarray
    pitch: float
    origin: np.ndarray

    def __post_init__(self):
        if not len(self.indices):
            raise ValueError("Mesh has no resolved volume; reduce pitch or closing")
        self.origin = np.array(self.origin, dtype=float, copy=True)
        self.indices = np.array(self.indices, dtype=int, copy=True)
        self.cells = frozenset(map(tuple, self.indices))

    @classmethod
    def from_mesh(cls, mesh, *, pitch=None, closing=0):
        """Voxelize the surface and fill enclosed cells; closing seals small gaps."""
        from scipy.ndimage import binary_closing, binary_fill_holes

        pitch = float(mesh.extents.max() / 96 if pitch is None else pitch)
        if not np.isfinite(pitch) or pitch <= 0:
            raise ValueError("pitch must be finite and positive")
        if isinstance(closing, bool) or not isinstance(closing, Integral) or closing < 0:
            raise ValueError("closing must be a nonnegative integer")
        if np.prod(np.ceil(mesh.extents / pitch) + 2 * closing + 5) > 4_000_000:
            raise ValueError("Voxel grid is too large; increase pitch")
        voxels = mesh.voxelized(pitch)
        padding = closing + 1
        surface = np.pad(voxels.matrix, padding)
        if closing:
            surface = binary_closing(surface, iterations=closing)
        filled = binary_fill_holes(surface)
        origin = voxels.transform[:3, 3] - padding * pitch
        return cls(np.argwhere(filled), pitch, origin)

    @property
    def points(self):
        return self.origin + self.indices * self.pitch


def occupied_cells(grid, placement):
    """Sample an item's solid on the target grid, also outside target bounds."""
    item = placement.item
    bounds = (np.array([-item.extents / 2, item.extents / 2])
              if isinstance(item, Cuboid) else item.mesh.bounds)
    corners = np.array(np.meshgrid(*bounds.T, indexing="ij")).reshape(3, -1).T
    corners = corners @ placement.rotation.T * placement.scale + placement.center
    low = np.ceil((corners.min(axis=0) - grid.origin) / grid.pitch - 1e-9).astype(int)
    high = np.floor((corners.max(axis=0) - grid.origin) / grid.pitch + 1e-9).astype(int)
    lengths = high - low + 1
    if np.any(lengths <= 0):
        return frozenset()
    if np.prod(lengths.astype(float)) > 2_000_000:
        raise ValueError("Item grid is too large; increase pitch")
    indices = np.indices(tuple(lengths)).reshape(3, -1).T + low
    local = ((grid.origin + indices * grid.pitch - placement.center) @ placement.rotation) / placement.scale
    if isinstance(item, Cuboid):
        inside = np.all(np.abs(local) <= item.extents / 2 + grid.pitch * 1e-9, axis=1)
    else:
        if not item.mesh.is_watertight:
            raise ValueError(f"Item {item.key!r} needs a watertight mesh for volume queries")
        inside = item.mesh.contains(local)
    return frozenset(map(tuple, indices[inside]))
