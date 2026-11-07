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
