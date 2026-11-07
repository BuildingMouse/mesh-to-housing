from dataclasses import dataclass
from functools import cached_property

import numpy as np

from ..meshes.loading import MeshLoader
from ..meshes.preparation import prepare_mesh
from .item import Item


@dataclass(frozen=True, eq=False)
class MeshItem(Item):
    source: object
    unit_scale: float = 1.0

    def __post_init__(self):
        super().__post_init__()
        if not np.isfinite(self.unit_scale) or self.unit_scale <= 0:
            raise ValueError("unit_scale must be finite and positive")

    @cached_property
    def mesh(self):
        mesh = prepare_mesh(MeshLoader.load(self.source))
        mesh.apply_scale(self.unit_scale)
        return mesh
