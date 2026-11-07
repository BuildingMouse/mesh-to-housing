from dataclasses import dataclass
import numpy as np

from .validation import positive_integer


@dataclass(frozen=True)
class TransformConstraints:
    scale_bounds: tuple = (1.0, 1.0)

    def __post_init__(self):
        bounds = np.asarray(self.scale_bounds, dtype=float)
        if bounds.shape != (2,) or not np.isfinite(bounds).all() or not 0 < bounds[0] <= bounds[1]:
            raise ValueError("scale_bounds must satisfy 0 < minimum <= maximum")
        object.__setattr__(self, "scale_bounds", tuple(bounds))

    def sample_scales(self, count):
        positive_integer(count, "scale count")
        return np.unique(np.geomspace(*self.scale_bounds, num=count))[::-1]

    def allows(self, placement):
        low, high = self.scale_bounds
        return low <= placement.scale <= high
