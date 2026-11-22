"""Voxel loss sessions and their candidate scorers, against set arithmetic on sampled cells."""
import numpy as np
import pytest

from mesh_to_housing import ExcessSurfaceConfig, OutsideVolumeConfig, UncoveredSurfaceConfig, UncoveredVolumeConfig

from ..reference import expanded, sampled_cells, skin

ADD_AND_REMOVE = [(True, 0), (True, 2), (True, 1), (False, 0), (True, 4), (False, 2), (False, 1), (False, 4)]


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
    session = loss_config(kind, grid_config, tolerance).build().session(task.target)
    scorer = session.scorer(placements)
    placed = []
    for adding, index in ADD_AND_REMOVE:
        if adding:
            placed.append(placements[index])
            session.add(placements[index])
        else:
            placed.remove(placements[index])
            session.remove(placements[index])
        union = frozenset().union(*(counted(placement) for placement in placed))
        expected = len(union) / reference if penalty else 1.0 - len(union) / reference
        assert session.value() == pytest.approx(expected, abs=1e-12)
        gains = [(-1 if penalty else 1) * len(counted(placement) - union) / reference for placement in placements]
        np.testing.assert_allclose(scorer.gains(), gains, atol=1e-12, rtol=0)
        np.testing.assert_allclose([session.gain(placement) for placement in placements], gains, atol=1e-12, rtol=0)
