"""The direction the target runs in, smooth over the whole target and the space around it."""
from functools import cached_property
from typing import Optional

import numpy as np

from .blur import BlurredSolid

# Room around the target, so that the field reaches past it and smoothing doesn't reflect it back at the box.
_PADDING = 8
_SMOOTHING = 2.0


class FlowField:
    def __init__(self, grid: "VoxelGrid"):
        self._grid = grid
        self._box = grid.box.padded(_PADDING)
        self._solid = np.pad(grid.solid_mask, _PADDING)
        self._depth = np.pad(grid.inner_depth, _PADDING)

    @cached_property
    def medial_indices(self) -> np.ndarray:
        return np.argwhere(self._medial) + self._box.low

    def direction_at(self, points: np.ndarray) -> np.ndarray:
        cells = self._cells(points)
        tensor = np.empty((len(cells[0]), 3, 3))
        for (a, b), component in self._tensor.items():
            tensor[:, a, b] = tensor[:, b, a] = component[cells]
        return np.linalg.eigh(tensor)[1][:, :, -1]

    def depth_at(self, points: np.ndarray) -> np.ndarray:
        """How deep inside the target each point lies, 0 outside."""
        return self._depth[self._cells(points)]

    def uphill_at(self, points: np.ndarray) -> np.ndarray:
        """The slope of the smoothed depth at each point. Points toward the middle of the part."""
        cells = self._cells(points)
        return np.stack([slope[cells] for slope in self._slopes], axis=1)

    def thin_direction(self, point: np.ndarray, heading: np.ndarray,
                       roundness: float = 1.5) -> Optional[np.ndarray]:
        """The direction across heading in which the part around the point is thinnest, or None when the part is
        about as wide one way as the other
        """
        position = np.asarray(self._cells(point[None]))[:, 0]
        radius = int(np.ceil(max(2.0, 2.0 * self._depth[tuple(position)])))
        low = np.maximum(position - radius, 0)
        high = np.minimum(position + radius + 1, self._box.shape)
        cells = np.argwhere(self._solid[tuple(slice(a, b) for a, b in zip(low, high))]) + low - position
        cells = cells[np.einsum("ij,ij->i", cells, cells) <= radius ** 2].astype(float)
        if len(cells) < 4:
            return None
        cells -= np.outer(cells @ heading, heading)
        spread, vectors = np.linalg.eigh(np.cov(cells.T))
        # The heading itself now has no spread, so the two across it are the largest two.
        thin, wide = spread[1], spread[2]
        if wide < roundness * max(thin, 1e-12):
            return None
        return vectors[:, 1]

    @cached_property
    def _medial(self) -> np.ndarray:
        from scipy.ndimage import maximum_filter

        return self._solid & (self._depth >= maximum_filter(self._depth, size=3))

    @cached_property
    def _slopes(self) -> list[np.ndarray]:
        from scipy.ndimage import gaussian_filter

        return np.gradient(gaussian_filter(self._depth, 1.0))

    @cached_property
    def _tensor(self) -> dict[tuple[int, int], np.ndarray]:
        from scipy.ndimage import gaussian_filter

        directions = self._part_directions()
        return {(a, b): gaussian_filter(directions[..., a] * directions[..., b], _SMOOTHING)
                for a in range(3) for b in range(a, 3)}

    def _part_directions(self) -> np.ndarray:
        """For every target cell, the direction in which the target spreads most within a gaussian window as wide
        as its part. Cells outside the target get none.
        """
        from scipy.ndimage import distance_transform_edt

        nearest = distance_transform_edt(~self._medial, return_distances=False, return_indices=True)
        cells = np.argwhere(self._solid)
        widths = self._depth[tuple(nearest[(slice(None), *cells.T)])]
        # Windows come in steps of half a doubling, so cells of a part share one blur.
        steps = np.rint(2 * np.log2(widths)).astype(int)
        directions = np.zeros((*self._solid.shape, 3))
        for step in np.unique(steps):
            at = tuple(cells[steps == step].T)
            blurred = BlurredSolid(self._solid, 2.0 ** (step / 2))
            slope = blurred.slope_at(at)
            # The blurred solid's second derivatives
            spread = blurred.bending_at(at) - slope[:, :, None] * slope[:, None, :] / blurred.value[at][:, None, None]
            directions[at] = np.linalg.eigh(spread)[1][:, :, -1]
        return directions

    def _cells(self, points: np.ndarray) -> tuple[np.ndarray, ...]:
        return self._box.clipped(self._grid.indices_of(np.asarray(points, dtype=float).reshape(-1, 3)))
