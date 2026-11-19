from dataclasses import dataclass

import numpy as np

from ..validation import positive_integer


@dataclass(frozen=True)
class VoxelGridConfig:
    """Lengths are in target units, so they keep their meaning at any pitch."""

    voxel_pitch: float = None
    resolution: int = 96
    gap_closing: float = 0.0
    target_samples: int = 3
    max_cells: int = 100_000_000

    def __post_init__(self):
        if self.voxel_pitch is not None and (not np.isfinite(self.voxel_pitch) or self.voxel_pitch <= 0):
            raise ValueError("voxel_pitch must be finite and positive")
        if not np.isfinite(self.gap_closing) or self.gap_closing < 0:
            raise ValueError("gap_closing must be finite and nonnegative")
        for name in ("resolution", "target_samples", "max_cells"):
            positive_integer(getattr(self, name), name)

    def pitch_for(self, mesh):
        return float(mesh.extents.max() / self.resolution if self.voxel_pitch is None else self.voxel_pitch)
