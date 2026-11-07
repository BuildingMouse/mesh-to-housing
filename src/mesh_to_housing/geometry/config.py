from dataclasses import dataclass
from numbers import Integral

import numpy as np


@dataclass(frozen=True)
class GeometryConfig:
    voxel_pitch: float = None
    closing: int = 0

    def __post_init__(self):
        if self.voxel_pitch is not None and (not np.isfinite(self.voxel_pitch) or self.voxel_pitch <= 0):
            raise ValueError("voxel_pitch must be finite and positive")
        if isinstance(self.closing, bool) or not isinstance(self.closing, Integral) or self.closing < 0:
            raise ValueError("closing must be a nonnegative integer")
