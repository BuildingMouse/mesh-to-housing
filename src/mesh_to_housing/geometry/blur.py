from functools import cached_property

import numpy as np


class BlurredSolid:
    """A boolean solid blurred by a gaussian of this width, in cells, with its slope and second derivatives.
    Everything outside the array counts as empty.
    """

    def __init__(self, solid: np.ndarray, width: float):
        self._solid = solid.astype(float)
        self.width = width

    @cached_property
    def value(self) -> np.ndarray:
        return self._blurred([0, 0, 0])

    def slope_at(self, cells: tuple[np.ndarray, ...]) -> np.ndarray:
        return np.stack([component[cells] for component in self._slope], axis=1)

    def bending_at(self, cells: tuple[np.ndarray, ...]) -> np.ndarray:
        """The second derivatives at the cells, as a symmetric 3 x 3 matrix for each."""
        bending = np.empty((len(cells[0]), 3, 3))
        for (a, b), component in self._bending.items():
            bending[:, a, b] = bending[:, b, a] = component[cells]
        return bending

    @cached_property
    def _slope(self) -> list[np.ndarray]:
        return [self._blurred([int(axis == along) for axis in range(3)]) for along in range(3)]

    @cached_property
    def _bending(self) -> dict[tuple[int, int], np.ndarray]:
        return {(a, b): self._blurred([int(axis == a) + int(axis == b) for axis in range(3)])
                for a in range(3) for b in range(a, 3)}

    def _blurred(self, order: list[int]) -> np.ndarray:
        from scipy.ndimage import gaussian_filter

        return gaussian_filter(self._solid, self.width, order=order, mode="constant")
