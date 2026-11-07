from dataclasses import dataclass

import numpy as np
import trimesh

from .placement import Placement


@dataclass(frozen=True)
class Construction:
    placements: tuple = ()

    def __post_init__(self):
        placements = tuple(self.placements)
        if not all(isinstance(placement, Placement) for placement in placements):
            raise TypeError("placements must contain Placement instances")
        object.__setattr__(self, "placements", placements)

    def __len__(self):
        return len(self.placements)

    def __iter__(self):
        return iter(self.placements)

    @property
    def transforms(self):
        return np.asarray([placement.transform for placement in self]).reshape(-1, 4, 4)

    def to_mesh(self):
        meshes = []
        for placement in self:
            mesh = placement.item.mesh.copy()
            mesh.apply_transform(placement.transform)
            meshes.append(mesh)
        return trimesh.util.concatenate(meshes) if meshes else trimesh.Trimesh()
