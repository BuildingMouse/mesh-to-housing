import numpy as np

from ..construction import Construction
from .cells import cell_indices


def outer_solids(grid: "VoxelGrid", construction: Construction) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The target's outer surface and the construction's solid, as boolean masks on one shared frame, and the cell index
    of the frame's first cell. Empty space enclosed inside the construction counts as part of its solid.
    """
    from scipy.ndimage import binary_fill_holes

    target_surface, target_low = grid.surface.mask, grid.box.low
    keys = list(grid.item_cells.occupied_by_each(construction))
    cells = cell_indices(np.unique(np.concatenate(keys)) if keys else np.zeros(0, dtype=np.int64))
    bounds = np.vstack((target_low, target_low + target_surface.shape - 1, cells))
    low = bounds.min(axis=0)
    shape = bounds.max(axis=0) - low + 1

    target = np.zeros(shape, dtype=bool)
    start = target_low - low
    target[tuple(slice(first, first + size) for first, size in zip(start, target_surface.shape))] = target_surface
    solid = np.zeros(shape, dtype=bool)
    solid[tuple((cells - low).T)] = True
    return target, binary_fill_holes(solid), low


def outer_surfaces(grid: "VoxelGrid", construction: Construction) -> tuple[np.ndarray, np.ndarray]:
    """The outer surfaces of the target and the construction, as boolean masks on one shared frame.
    Empty space enclosed inside the construction counts as filled, so only surface that faces the outside is kept.
    """
    from scipy.ndimage import binary_erosion

    target, solid, _ = outer_solids(grid, construction)
    return target, solid & ~binary_erosion(solid)


def nearest_distances(from_mask: np.ndarray, to_mask: np.ndarray, pitch: float) -> np.ndarray:
    """The distance from each cell of from_mask to the nearest cell of to_mask, in target units."""
    from scipy.ndimage import distance_transform_edt

    # The transform measures how far each True cell is from the nearest False one, so to_mask is inverted.
    return distance_transform_edt(~to_mask)[from_mask] * pitch
