from abc import ABC, abstractmethod
from dataclasses import dataclass

import numpy as np
import trimesh


@dataclass(frozen=True, eq=False)
class Item(ABC):
    key: str

    def __post_init__(self):
        if not isinstance(self.key, str) or not self.key.strip():
            raise ValueError("Item key must be a nonempty string")

    @property
    @abstractmethod
    def mesh(self) -> trimesh.Trimesh:
        pass

    @property
    def extents(self):
        return np.asarray(self.mesh.extents).copy()

    @property
    def bounds(self):
        return np.array(self.mesh.bounds)

    @property
    def box_center(self):
        return self.bounds.mean(axis=0)

    @property
    def box_size(self) -> np.ndarray:
        """The sides of the bounding box along the item's own axes."""
        low, high = self.bounds
        return high - low

    def contains(self, points):
        if not self.mesh.is_watertight:
            raise ValueError(f"Item {self.key!r} needs a watertight mesh for volume queries")
        return self.mesh.contains(points)
