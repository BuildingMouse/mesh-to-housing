from dataclasses import dataclass
from functools import cached_property

import numpy as np
import trimesh

from .item import Item


@dataclass(frozen=True, eq=False)
class Cuboid(Item):
    dimensions: tuple

    def __post_init__(self):
        super().__post_init__()
        dimensions = np.asarray(self.dimensions, dtype=float)
        if dimensions.shape != (3,) or not np.isfinite(dimensions).all() or np.any(dimensions <= 0):
            raise ValueError("dimensions must contain three finite positive lengths")
        object.__setattr__(self, "dimensions", tuple(dimensions))

    @cached_property
    def mesh(self):
        return trimesh.creation.box(extents=self.dimensions)

    @property
    def extents(self):
        return np.asarray(self.dimensions)

    @property
    def bounds(self):
        return np.array([-self.extents / 2, self.extents / 2])

    def contains(self, points):
        return np.all(np.abs(points) <= self.extents / 2 * (1 + 1e-9), axis=1)
