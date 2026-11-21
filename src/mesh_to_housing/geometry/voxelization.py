"""Turning a mesh into a VoxelGrid."""
from functools import lru_cache
from math import ceil

import numpy as np
import trimesh

from .voxel_grid import VoxelGrid, VoxelGridConfig


@lru_cache(maxsize=8)
def voxelize(mesh: trimesh.Trimesh, config: VoxelGridConfig) -> VoxelGrid:
    """The cells the mesh fills at least halfway, plus cells that hold thin parts.

    Each cell is checked on a finer grid, config.target_samples steps along each axis. Thin parts
    may never fill half of any cell, so a cell that holds most of a thin part is kept too.
    """
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

    # A surface voxel straddles the mesh, so it counts as half filled. Otherwise the target would grow with the pitch.
    fill = 2 * solid.astype(np.uint8) - surface.astype(np.uint8)
    half_filled = _cell_blocks(fill, samples).sum(axis=(1, 3, 5)) >= samples ** 3
    thick = maximum_filter(minimum_filter(solid, size=2 * samples + 1), size=2 * samples + 1)
    thin_amount = _cell_blocks(solid, samples).sum(axis=(1, 3, 5)) * ~_cell_blocks(thick, samples).any(axis=(1, 3, 5))
    holds_thin_part = (thin_amount > 0) & (2 * thin_amount >= maximum_filter(thin_amount, size=3))
    indices = np.argwhere(half_filled | holds_thin_part)
    origin = voxels.transform[:3, 3] + ((samples - 1) / 2 - padding) * fine_pitch
    return VoxelGrid(indices, fine_pitch * samples, origin, config)


def _cell_blocks(fine: np.ndarray, samples: int) -> np.ndarray:
    """The fine voxels grouped into one block of samples³ per cell."""
    cells = np.array(fine.shape) // samples
    return fine[:cells[0] * samples, :cells[1] * samples, :cells[2] * samples].reshape(
        cells[0], samples, cells[1], samples, cells[2], samples)
