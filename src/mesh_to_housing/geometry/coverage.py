"""Which parts of the target surface the placements cover."""
from typing import Iterator, Sequence

import numpy as np

from ..placement import Placement
from .cells import CellKeys, select_keys


def covered_surface_keys(grid: "VoxelGrid", placements: Sequence[Placement], tolerance: float, *,
                         skin_only: bool = False) -> Iterator[CellKeys]:
    """For each placement, the target surface cells within the tolerance of the cells it occupies.
    With skin_only, only the placement's outer layer of cells counts, so surface that is not visible stays uncovered.
    """
    return select_keys(grid.item_cells.dilated_each(placements, tolerance, skin_only=skin_only), grid.surface.contains)


def uncovered_surface_keys(grid: "VoxelGrid", placements: Sequence[Placement], tolerance: float, *,
                           skin_only: bool = False) -> CellKeys:
    """The target surface cells that no placement comes within the tolerance of."""
    covered = list(covered_surface_keys(grid, placements, tolerance, skin_only=skin_only))
    return np.setdiff1d(grid.surface.keys, np.concatenate(covered) if covered else np.zeros(0, dtype=np.int64))
