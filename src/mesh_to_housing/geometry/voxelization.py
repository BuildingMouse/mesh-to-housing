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
    shell, corner = _surface_voxels(mesh, fine_pitch)
    surface = np.pad(shell, padding)
    if closing:
        surface = binary_closing(surface, iterations=closing)
    solid = binary_fill_holes(surface)

    # A surface voxel straddles the mesh, so it counts as half filled. Otherwise the target would grow with the pitch.
    fill = 2 * solid.astype(np.uint8) - surface.astype(np.uint8)
    half_filled = _cell_blocks(fill, samples).sum(axis=(1, 3, 5)) >= samples ** 3
    thick = maximum_filter(minimum_filter(solid, size=2 * samples + 1), size=2 * samples + 1)
    thin_amount = _cell_blocks(solid, samples).sum(axis=(1, 3, 5)) * ~_cell_blocks(thick, samples).any(axis=(1, 3, 5))
    holds_thin_part = (thin_amount > 0) & (2 * thin_amount >= maximum_filter(thin_amount, size=3))
    # Rounding to cells can leave a few empty cells walled in, which the target's outer surface shouldn't show.
    indices = np.argwhere(binary_fill_holes(half_filled | holds_thin_part))
    origin = corner + ((samples - 1) / 2 - padding) * fine_pitch
    return VoxelGrid(indices, fine_pitch * samples, origin, config)


def _surface_voxels(mesh: trimesh.Trimesh, pitch: float, triangles_per_batch: int = 1 << 18):
    """The voxels the surface passes through, as a boolean array, and the position of its first voxel.
    Faces are split a batch at a time, so memory peak stays small at fine pitches.
    """
    from trimesh.remesh import subdivide_to_size

    max_edge = pitch / 2
    corners = mesh.triangles
    low = np.round(corners.reshape(-1, 3).min(axis=0) / pitch).astype(int)
    high = np.round(corners.reshape(-1, 3).max(axis=0) / pitch).astype(int)
    shell = np.zeros(high - low + 1, dtype=bool)
    longest = np.linalg.norm(corners - np.roll(corners, 1, axis=1), axis=2).max(axis=1)
    # Each split turns a face into four, so this is about how many triangles each face ends as.
    triangles = 4.0 ** np.ceil(np.log2(np.maximum(longest / max_edge, 1.0)))
    batch = np.cumsum(triangles) // triangles_per_batch
    for faces in np.split(mesh.faces, np.flatnonzero(np.diff(batch)) + 1):
        used, local = np.unique(faces, return_inverse=True)
        vertices, _ = subdivide_to_size(mesh.vertices[used], local.reshape(-1, 3), max_edge=max_edge, max_iter=10)
        shell[tuple((np.round(vertices / pitch).astype(int) - low).T)] = True
    return shell, low * pitch


def _cell_blocks(fine: np.ndarray, samples: int) -> np.ndarray:
    """The fine voxels grouped into one block of samples³ per cell."""
    cells = np.array(fine.shape) // samples
    return fine[:cells[0] * samples, :cells[1] * samples, :cells[2] * samples].reshape(
        cells[0], samples, cells[1], samples, cells[2], samples)
