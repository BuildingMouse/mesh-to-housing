from collections import Counter

import numpy as np
import pytest
from pydantic import ValidationError

from mesh_to_housing import (
    CombinedLossConfig, Construction, Cuboid, FittingPipeline, ItemOverlapConfig, ItemOverlapLoss, Loss, LossTerm,
    Placement, UncoveredVolumeConfig,
)
from mesh_to_housing.geometry.cells import cell_keys
from mesh_to_housing.geometry.voxel_grid import VoxelGrid

from ..reference import sampled_cells


@pytest.mark.parametrize("shell_cells", [None, 0.5, 2.25])
def test_overlap_values_and_gains_follow_adds_and_removes(task, grid_config, grid, placements, shell_cells):
    shell = None if shell_cells is None else shell_cells * grid.pitch
    loss = Loss.from_config(ItemOverlapConfig(grid=grid_config, shell=shell))
    session = loss.session(task.target)
    scorer = session.scorer(placements)
    limit = 1.0 if shell_cells is None else shell_cells

    def visible(cell):
        local = np.asarray(cell) - grid.box.low
        inside = np.all(local >= 0) and np.all(local < grid.box.shape)
        return not inside or grid.inner_depth[tuple(local)] <= limit

    cells = {placement: {cell for cell in sampled_cells(grid, placement) if visible(cell)}
             for placement in placements}

    def overlap(placed):
        counts = Counter(cell for placement in placed for cell in cells[placement])
        return sum(count - 1 for count in counts.values()) / len(grid.surface)

    placed = []

    def check():
        expected = overlap(placed)
        assert session.value() == pytest.approx(expected, abs=1e-12)
        assert loss(task.target, Construction(placed)) == pytest.approx(expected, abs=1e-12)
        gains = [expected - overlap([*placed, candidate]) for candidate in placements]
        np.testing.assert_allclose(scorer.gains(), gains, atol=1e-12, rtol=0)
        np.testing.assert_allclose([session.gain(candidate) for candidate in placements], gains, atol=1e-12, rtol=0)

    check()
    order = (0, 2, 1, 6, 4, len(placements) - 1, len(placements) - 1, len(placements) - 1)
    for index in order:
        placed.append(placements[index])
        session.add(placements[index])
        check()
    for index in reversed(order):
        placed.remove(placements[index])
        session.remove(placements[index])
        check()


@pytest.mark.parametrize("offset, shell_cells, counted", [
    ((0, 0, 0), None, True),
    ((1, 1, 1), None, False),
    ((1, 1, 1), 2.0, True),
    ((1, 1, 1), 1.5, False),
    ((0, 0, 0), 0.5, False),
    ((-1, 0, 0), None, True),
    ((-20, 0, 0), 0.5, True),
])
def test_shell_counts_only_shallow_or_outside_overlap(task, grid_config, grid, offset, shell_cells, counted):
    item = Cuboid("cell", (grid.pitch / 2,) * 3)
    placement = Placement(item, grid.points_of(grid.box.low + offset), np.eye(3))
    shell = None if shell_cells is None else shell_cells * grid.pitch
    session = ItemOverlapLoss(ItemOverlapConfig(grid=grid_config, shell=shell)).session(task.target)
    scorer = session.scorer([placement])
    for count in range(1, 4):
        session.add(placement)
        assert session.value() == pytest.approx((count - 1) * counted / len(grid.surface))
        assert session.gain(placement) == pytest.approx(-counted / len(grid.surface))
    np.testing.assert_allclose(scorer.gains(), [-counted / len(grid.surface)])
    np.testing.assert_allclose(session.scorer([placement]).gains(), scorer.gains())
    for count in (2, 1, 0):
        session.remove(placement)
        assert session.value() == pytest.approx(max(count - 1, 0) * counted / len(grid.surface))
    np.testing.assert_allclose(scorer.gains(), [0])
    np.testing.assert_array_equal(session.scorer([]).gains(), [])


def test_depth_lookup_handles_holes_outside_cells_and_empty_input():
    indices = np.indices((5, 5, 5)).reshape(3, -1).T - 2
    indices = indices[np.any(indices != (1, 1, 1), axis=1)]
    grid = VoxelGrid(indices, pitch=0.25, origin=np.zeros(3))
    asked = cell_keys(np.array([(0, 0, 0), (2, 0, 0), (1, 1, 1), (3, 0, 0), (-3, 0, 0)]))
    np.testing.assert_allclose(grid.depth_of(asked), [np.sqrt(3), 1, 0, 0, 0])
    np.testing.assert_array_equal(grid.depth_of(np.zeros(0, dtype=np.int64)), [])


@pytest.mark.parametrize("shell", [None, 0.125])
def test_overlap_config_round_trips_alone_and_in_combined_losses(grid_config, shell):
    config = ItemOverlapConfig(grid=grid_config, shell=shell)
    pipeline = FittingPipeline(losses={
        "overlap": config,
        "fit": CombinedLossConfig(terms={
            "coverage": LossTerm(loss=UncoveredVolumeConfig(grid=grid_config), loss_scale=1),
            "overlap": LossTerm(loss=config, loss_scale=0.25),
        }),
    })
    assert FittingPipeline.from_yaml(pipeline.to_yaml()) == pipeline
    assert FittingPipeline.from_yaml(pipeline.to_yaml(full=True)) == pipeline
    assert isinstance(Loss.from_config(config), ItemOverlapLoss)


@pytest.mark.parametrize("shell", [0, -0.1, float("inf"), float("nan")])
def test_overlap_rejects_invalid_shell_depths(shell):
    with pytest.raises(ValidationError, match="shell"):
        ItemOverlapConfig(shell=shell)
