from functools import cached_property
from math import ceil

import numpy as np

from .blur import BlurredSolid
from .cells import CellBox, CellKeys, cell_indices, cell_keys
from .morphology import ball_mask

_GRAIN_SMOOTHING = 3.0
# Room for the whole blur, which gaussian_filter cuts off at four widths.
_GRAIN_PADDING = ceil(4 * _GRAIN_SMOOTHING)


class TargetSurface:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid
        self._near_masks = {}
        self._thickness = {}
        self._roughness = {}

    @cached_property
    def mask(self) -> np.ndarray:
        """The surface cells as a boolean array over the grid's box."""
        from scipy.ndimage import binary_erosion

        solid = self._grid.solid_mask
        return solid & ~binary_erosion(solid)

    @cached_property
    def keys(self) -> CellKeys:
        return cell_keys(np.argwhere(self.mask) + self._grid.box.low)

    @cached_property
    def indices(self) -> np.ndarray:
        return cell_indices(self.keys)

    def __len__(self) -> int:
        return len(self.keys)

    def contains(self, keys: CellKeys) -> np.ndarray:
        return self._grid.box.lookup(self.mask, keys)

    def near(self, keys: CellKeys, radius: float) -> np.ndarray:
        """Whether each cell's center lies within radius of a surface cell's center."""
        if radius not in self._near_masks:
            from scipy.ndimage import binary_dilation

            grid = self._grid
            reach = ceil(radius / grid.pitch)
            box = grid.box.padded(reach)
            grown = binary_dilation(np.pad(self.mask, reach), structure=ball_mask(grid.pitch, radius))
            self._near_masks[radius] = box, grown
        box, grown = self._near_masks[radius]
        return box.lookup(grown, keys)

    def index_of(self, keys: CellKeys) -> np.ndarray:
        """Where each of these surface cells sits in keys."""
        return np.searchsorted(self.keys, keys)

    @cached_property
    def normals(self) -> np.ndarray:
        return self._grid.outward_normals(self.indices)

    def grain_at(self, points: np.ndarray, normals: np.ndarray,
                 contrast: float = 0.25) -> tuple[np.ndarray, np.ndarray]:
        """Unit directions along the surface in which it bends least"""
        cells = self._grain_box.clipped(self._grid.indices_of(np.asarray(points, dtype=float).reshape(-1, 3)))
        hessian = self._blurred.bending_at(cells)
        across = np.eye(3) - normals[:, :, None] * normals[:, None, :]
        values, vectors = np.linalg.eigh(across @ hessian @ across)
        normal_like = np.argmax(np.abs(np.einsum("nij,ni->nj", vectors, normals)), axis=1)
        rows = np.arange(len(normals))
        keep = np.array([[column for column in range(3) if column != skip] for skip in normal_like])
        bends = np.abs(values[rows[:, None], keep])
        least = keep[rows, np.argmin(bends, axis=1)]
        difference = np.abs(bends[:, 0] - bends[:, 1])
        slope = np.linalg.norm(self._blurred.slope_at(cells), axis=1)
        curved = difference >= slope / max(self._grid.box.shape)
        return vectors[rows, :, least], curved & (difference >= contrast * np.maximum(bends.sum(axis=1), 1e-12))

    def thickness(self, radius: float) -> np.ndarray:
        """How thick the target is around each surface cell, in target units. It finds the deepest point inside the
        target within radius of the cell and doubles it, so parts thicker than twice radius read as about twice
        radius thick.
        """
        if radius not in self._thickness:
            from scipy.ndimage import maximum_filter

            grid = self._grid
            footprint = ball_mask(grid.pitch, max(radius, grid.pitch))
            deepest = maximum_filter(grid.inner_depth, footprint=footprint, mode="constant")
            thickness = 2.0 * deepest[tuple((self.indices - grid.box.low).T)] * grid.pitch
            thickness.flags.writeable = False
            self._thickness[radius] = thickness
        return self._thickness[radius]

    def roughness(self, radius: float) -> np.ndarray:
        if radius not in self._roughness:
            grid = self._grid
            values = surface_roughness(self.mask, self.indices - grid.box.low, self.normals, grid.pitch, radius)
            values.flags.writeable = False
            self._roughness[radius] = values
        return self._roughness[radius]

    def thinness(self, radius: float) -> np.ndarray:
        """How thin the target is around each surface cell: 0 where it is at least twice radius thick, rising toward
        1 as it gets thinner.
        """
        return np.clip(1.0 - self.thickness(radius) / (2 * radius), 0.0, 1.0)

    @cached_property
    def tree(self):
        """A search tree over the centers of the surface cells."""
        from scipy.spatial import cKDTree

        return cKDTree(self._grid.points_of(self.indices))

    @cached_property
    def _grain_box(self) -> CellBox:
        return self._grid.box.padded(_GRAIN_PADDING)

    @cached_property
    def _blurred(self) -> BlurredSolid:
        return BlurredSolid(np.pad(self._grid.solid_mask, _GRAIN_PADDING), _GRAIN_SMOOTHING)

    @cached_property
    def points(self) -> np.ndarray:
        """Points on the surface itself, half a cell outward from the centers of the surface cells."""
        grid = self._grid
        return grid.origin + self.indices * grid.pitch + self.normals * grid.pitch / 2


def surface_roughness(mask: np.ndarray, cells: np.ndarray, normals: np.ndarray, pitch: float,
                      radius: float) -> np.ndarray:
    """How much a surface bends around each of its cells: 0 on a flat face, rising toward 1 at sharp edges and
    small details.

    It looks at the outward normals of the surface cells within radius and measures how far they are from all
    lying along one line. The direction along that line doesn't matter, so the two sides of a thin flat part, whose
    normals point opposite ways, still count as flat.
    """
    from scipy.ndimage import convolve

    ball = ball_mask(pitch, max(radius, pitch)).astype(float)
    at_cells = tuple(np.asarray(cells, dtype=int).T)
    count = convolve(mask.astype(float), ball, mode="constant")[at_cells]
    spread = np.zeros((len(normals), 3, 3))
    field = np.zeros(mask.shape)
    for row in range(3):
        for column in range(row, 3):
            field[at_cells] = normals[:, row] * normals[:, column]
            spread[:, row, column] = spread[:, column, row] = convolve(field, ball, mode="constant")[at_cells] / count
    # The largest eigenvalue is 1 when the normals lie along one line and 1/3 when they point every way.
    largest = np.linalg.eigvalsh(spread)[:, -1]
    return np.clip(1.5 * (1.0 - largest), 0.0, 1.0)


def solid_normals(solid: np.ndarray, cells: np.ndarray) -> np.ndarray:
    """Outward unit normals of a boolean solid at the given cells, from the slope of a slightly blurred copy."""
    from scipy.ndimage import gaussian_filter

    blurred = gaussian_filter(np.pad(solid, 2).astype(float), sigma=1.0)
    local = np.asarray(cells, dtype=int).reshape(-1, 3) + 2
    # These are the central differences np.gradient would take, worked out only at these cells.
    # The padding keeps the cells away from the edges of the array.
    normals = -np.stack([(blurred[tuple((local + step).T)] - blurred[tuple((local - step).T)]) / 2.0
                         for step in np.eye(3, dtype=int)], axis=1)
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    return np.where(lengths > 0, normals / np.where(lengths > 0, lengths, 1), (0.0, 0.0, 1.0))
