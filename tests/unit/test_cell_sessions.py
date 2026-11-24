"""Voxel loss sessions and their candidate scorers, against set arithmetic on sampled cells."""
import numpy as np
import pytest

from mesh_to_housing import (
    ExcessSurfaceConfig, Loss, OutsideVolumeConfig, UncoveredSurfaceConfig, UncoveredVolumeConfig,
)
from mesh_to_housing.geometry.cells import cell_keys
from mesh_to_housing.geometry.coverage import covered_surface_keys
from mesh_to_housing.losses.cell_sessions import CoverageSession, PenaltySession

from ..reference import expanded, follow, sampled_cells, skin


def loss_config(kind, grid_config, tolerance):
    if kind == "uncovered volume":
        return UncoveredVolumeConfig(grid=grid_config)
    if kind == "outside volume":
        return OutsideVolumeConfig(grid=grid_config)
    if kind == "excess surface":
        return ExcessSurfaceConfig(grid=grid_config, surface_tolerance=tolerance)
    return UncoveredSurfaceConfig(grid=grid_config, surface_tolerance=tolerance,
                                  skin_only=kind == "uncovered surface, skin only")


@pytest.mark.parametrize("kind", ["uncovered volume", "outside volume", "uncovered surface",
                                  "uncovered surface, skin only", "excess surface"])
def test_values_and_gains_follow_adds_and_removes(task, grid_config, grid, placements, kind):
    tolerance = grid.pitch * 1.1
    target = frozenset(map(tuple, grid.indices))
    surface = skin(target)

    def counted(placement):
        occupied = sampled_cells(grid, placement)
        if kind == "uncovered volume":
            return occupied & target
        if kind == "outside volume":
            return occupied - target
        if kind == "excess surface":
            return skin(occupied) - expanded(target, grid.pitch, tolerance)
        sources = skin(occupied) if kind.endswith("skin only") else occupied
        return expanded(sources, grid.pitch, tolerance) & surface

    reference = len(target if kind.endswith("volume") else surface)
    penalty = kind in ("outside volume", "excess surface")
    session = Loss.from_config(loss_config(kind, grid_config, tolerance)).session(task.target)
    follow(session, placements, counted, reference, penalty)

def weight_of(keys):
    """A fixed, uneven weight for each cell."""
    return 0.5 + (np.asarray(keys) % 7) * 0.4


@pytest.mark.parametrize("penalty", [False, True])
def test_weighted_sessions_sum_the_weights_of_scored_cells(task, grid, placements, penalty):
    tolerance = grid.pitch * 1.1
    surface = skin(frozenset(map(tuple, grid.indices)))
    reference = float(weight_of(cell_keys(np.array(sorted(surface)))).sum())

    def counted(placement):
        return expanded(sampled_cells(grid, placement), grid.pitch, tolerance) & surface

    def cells_of(placements):
        return covered_surface_keys(grid, placements, tolerance)

    def weighed(cells):
        return float(weight_of(cell_keys(np.array(sorted(cells)).reshape(-1, 3))).sum())

    session = (PenaltySession if penalty else CoverageSession)(cells_of, reference, weights=weight_of)
    follow(session, placements, counted, reference, penalty, weighed)
