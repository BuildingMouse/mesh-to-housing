from dataclasses import dataclass
from typing import Literal, get_args

import numpy as np

from ...utils.values import positive_integer
from ...geometry.coverage import uncovered_surface_keys
from ...geometry.rotations import random_rotations, rotation_about, rotation_onto
from ...geometry.settings import SurfaceSettings
from ...placement import Placement
from .base import Proposals

Orientation = Literal["surface", "random"]


@dataclass(frozen=True)
class ResidualProposals(SurfaceSettings, Proposals):
    spots: int = 32
    spins: int = 2
    scales: int = 5
    orientation: Orientation = "surface"
    skin_only: bool = True

    def __post_init__(self):
        super().__post_init__()
        for name in ("spots", "spins", "scales"):
            positive_integer(getattr(self, name), name)
        if self.orientation not in get_args(Orientation):
            raise ValueError("orientation must be 'surface' or 'random'")

    def propose(self, task, placements, rng):
        grid = self.voxel_grid(task.target)
        uncovered = uncovered_surface_keys(grid, placements, self.tolerance_for(task.target),
                                           skin_only=self.skin_only)
        available = grid.surface.index_of(uncovered)
        if not len(available):
            return []
        spots = available[rng.choice(len(available), min(self.spots, len(available)), replace=False)]
        scales = task.constraints.sample_scales(self.scales)
        proposals = []
        for point, normal in zip(grid.surface.points[spots], grid.surface.normals[spots]):
            for item in task.catalog:
                for rotation, anchor in self._orientations(item, normal, rng):
                    for scale in scales:
                        proposals.append(Placement.with_point_at(item, anchor, point, rotation, scale))
        return proposals

    def _orientations(self, item, normal, rng):
        if self.orientation == "random":
            return [(rotation, item.box_center) for rotation in random_rotations(self.spins, rng)]
        low, high = item.bounds
        thinnest = int(np.argmin(high - low))
        outer_face = (low + high) / 2
        outer_face[thinnest] = high[thinnest]
        facing_out = rotation_onto(np.eye(3)[thinnest], normal)
        return [(rotation_about(normal, angle) @ facing_out, outer_face)
                for angle in rng.uniform(0, 2 * np.pi, self.spins)]
