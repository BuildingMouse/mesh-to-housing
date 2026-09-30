from dataclasses import dataclass, field

import numpy as np
import trimesh


@dataclass(eq=False)
class Shape:
    """Fixed local geometry with uniform scaling; currently created with box()."""

    mesh: trimesh.Trimesh
    scale_bounds: tuple = (0.2, 2.0)
    box_extents: tuple = field(default=None, init=False)

    def __post_init__(self):
        bounds = np.asarray(self.scale_bounds, dtype=float)
        if bounds.shape != (2,) or not np.isfinite(bounds).all() or not 0 < bounds[0] <= bounds[1]:
            raise ValueError("scale_bounds must satisfy 0 < minimum <= maximum")
        self.scale_bounds = tuple(bounds)

    @property
    def extents(self):
        return self.mesh.extents.copy()

    @property
    def size(self):
        return float(self.extents.max())

    @classmethod
    def box(cls, size, scale_bounds=(0.2, 2.0), *, proportions=(0.25, 0.25, 1)):
        """Create a fixed box whose longest side is size at scale 1."""
        proportions = np.asarray(proportions, dtype=float)
        if proportions.shape != (3,) or not np.isfinite(proportions).all() or np.any(proportions <= 0):
            raise ValueError("proportions must contain three finite positive lengths")
        if not np.isfinite(size) or size <= 0:
            raise ValueError("size must be finite and positive")
        extents = size * proportions / proportions.max()
        shape = cls(trimesh.creation.box(extents=extents), scale_bounds)
        shape.box_extents = tuple(extents)
        return shape
