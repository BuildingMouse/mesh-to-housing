import numpy as np
import pytest
import trimesh

from mesh_to_housing import (
    CandidateSettings, Cuboid, Fill, FittingPipeline, FittingTask, ItemKinds, Placement, RandomPool, ScoreAll,
    Shortlist, Stage, Swaps, UncoveredVolumeConfig,
)


def two_item_task():
    catalog = (Cuboid("tile", (0.6, 0.6, 0.15)), Cuboid("column", (0.15, 0.15, 0.6)))
    return FittingTask(trimesh.creation.box(extents=(1.0, 1.5, 1.0)), catalog, 4)


def test_item_kinds_keep_only_the_named_items(grid_config):
    pipeline = FittingPipeline(
        losses={"volume": UncoveredVolumeConfig(grid=grid_config)},
        proposals={"pool": RandomPool(grid_config, centers=6, orientations=2, scales=1)},
        steps=(Stage(minimize="volume", steps=(Fill(),),
                     candidates=CandidateSettings(fixed=("pool",), filters=(ItemKinds(("column",)),))),),
    )
    construction = pipeline.fit(two_item_task(), seed=1)
    assert len(construction) and {placement.item.key for placement in construction} == {"column"}


@pytest.mark.parametrize("shortlist", [False, True], ids=["score_all", "shortlist"])
def test_nested_filters_apply_to_inherited_pools_and_restore_them(grid_config, monkeypatch, shortlist):
    task = two_item_task()
    tile, column = task.catalog
    placements = [Placement(tile, (0.0, 0.3, 0.0), np.eye(3)),
                  Placement(column, (-0.3, -0.4, 0.0), np.eye(3)),
                  Placement(column, (0.3, -0.4, 0.0), np.eye(3))]
    monkeypatch.setattr(RandomPool, "propose", lambda self, *args: placements)
    loss = UncoveredVolumeConfig(grid=grid_config)
    select = Shortlist(loss) if shortlist else ScoreAll()
    filtered = Stage(candidates=CandidateSettings(filters=(ItemKinds(("column",)),)),
                     steps=(Fill(items=1), Stage(minimize="other", steps=(Fill(),))))
    pipeline = FittingPipeline(
        losses={"volume": loss, "other": loss}, proposals={"pool": RandomPool(grid_config)},
        steps=(Stage(minimize="volume", select=select, candidates=CandidateSettings(fixed=("pool",)),
                     steps=(filtered, Fill())),),
    )
    construction = pipeline.fit(task, seed=1)
    assert [placement.item.key for placement in construction] == ["column", "column", "tile"]
    assert set(construction) == set(placements)


def test_swaps_offer_the_other_items_in_the_same_spot():
    task = two_item_task()
    tile, column = task.catalog
    placement = Placement(tile, (0.1, 0.2, 0.0), np.eye(3), 1.0)
    (swapped,) = Swaps().around(task, placement)
    assert swapped.item is column and swapped.scale == placement.scale
    np.testing.assert_allclose(swapped.box_center, placement.box_center)
    np.testing.assert_allclose(swapped.rotation, placement.rotation)
