from typing import Literal

import numpy as np

from ...utils.values import PositiveInt
from ...geometry.cells import cell_indices, cell_keys
from ...geometry.coverage import uncovered_surface_keys
from ...geometry.rotations import random_rotations, rotation_about, rotation_onto
from ...geometry.settings import SurfaceSettings
from ...placement import Placement
from .base import ProposalSource, sample_positions

class ResidualProposals(SurfaceSettings, ProposalSource):
    """Candidates at random spots of the target surface that the construction doesn't cover yet."""

    type: Literal["residual"] = "residual"
    spots: PositiveInt = 32
    spins: PositiveInt = 2
    scales: PositiveInt = 5
    orientation: Literal["surface", "random"] = "surface"
    skin_only: bool = True

    def propose(self, task, placements, rng):
        grid = self.voxel_grid(task.target)
        uncovered = uncovered_surface_keys(grid, placements, self.tolerance_for(task.target),
                                           skin_only=self.skin_only)
        cells = cell_indices(uncovered)
        if not len(cells):
            return []
        spots = grid.surface.index_of(cell_keys(cells[sample_positions(rng, len(cells), self.spots)]))
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
