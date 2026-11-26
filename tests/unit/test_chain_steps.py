from dataclasses import replace
from typing import Callable

import numpy as np
import pytest
import trimesh

from mesh_to_housing import (
    ChainFill, ChainMoves, ChainPolish, CombinedLossConfig, ExcessSurfaceConfig, FittingPipeline,
    FittingTask, ItemOverlapConfig, ItemSettings, Loss, LossConfig, LossTerm, MedialChains, Nudges, Placement, Polish,
    Refine, Shortlist, SizeRange, Stage, SurfaceChains, TransformConstraints, UncoveredSurfaceConfig,
    UncoveredVolumeConfig, VoxelGridConfig,
)
from mesh_to_housing.fitting import ChainGroup, ChainSource
from mesh_to_housing.fitting.chain_steps import best_run
from mesh_to_housing.fitting.state import FitState, Scope
from mesh_to_housing.losses.base import implements

from ..chains import COLUMN, straight_chain

GRID = VoxelGridConfig(resolution=24, target_samples=1)
STILL = ChainMoves(grid=GRID, shift=0, turn=0, rescale=1, ends=False)


class ScoreConfig(LossConfig):
    score: Callable


@implements(ScoreConfig)
class ScoreLoss(Loss):
    def __call__(self, target, construction):
        return self.config.score(construction.placements)


class OfferedChains(ChainSource):
    def __init__(self, chains=()):
        self.chains = chains
        self.asked = 0

    def propose_chains(self, task, placements, rng):
        self.asked += 1
        return list(self.chains)


@pytest.fixture
def chain_task():
    return FittingTask(trimesh.creation.box(extents=(3.0, 0.3, 0.3)), (COLUMN,), 8,
                       TransformConstraints(scale_bounds=(0.2, 2.0)))


def state_for(task, loss, proposals=None, scope=None):
    return FitState(task, np.random.default_rng(0), {"fit": loss}, proposals or {}, scope or Scope(loss="fit"))


def chain_pipeline(break_cost=None, shortlist=False):
    loss = CombinedLossConfig(terms={
        "surface": LossTerm(UncoveredSurfaceConfig(grid=GRID, skin_only=True), 1),
        "excess": LossTerm(ExcessSurfaceConfig(grid=GRID), 1),
        "overlap": LossTerm(ItemOverlapConfig(grid=GRID), 1),
    })
    return FittingPipeline(
        losses={"fit": loss},
        proposals={"medial": MedialChains(grid=GRID, chains=2), "surface": SurfaceChains(grid=GRID, chains=2)},
        steps=(Stage(minimize="fit", select=Shortlist(UncoveredVolumeConfig(grid=GRID)) if shortlist else None,
                     steps=(ChainFill(chains=("medial", "surface"), shortlist=3, refresh_every=2),
                            ChainPolish(moves=ChainMoves(grid=GRID), rounds=1, break_cost=break_cost,
                                        nudges=Nudges(grid=GRID)))),),
    )


@pytest.mark.parametrize("break_cost", [None, 0.0])
@pytest.mark.parametrize("shortlist", [False, True])
def test_chain_steps_fill_and_polish_whole_chains_within_the_budget(chain_task, break_cost, shortlist):
    pipeline = chain_pipeline(break_cost, shortlist)
    (stage,) = pipeline.steps
    state = FitState(chain_task, np.random.default_rng(0), pipeline.losses, pipeline.proposals,
                     Scope(loss="fit", selection=stage.select or Scope().selection))
    for step in stage.steps:
        before = state.selector.value()
        step.run(state)
        assert state.selector.value() < before
    assert state.chains and len(state.placements) <= chain_task.max_items
    chained = [placement for chain in state.chains for placement in chain.placements]
    assert len(chained) == len(set(chained))
    assert set(chained) <= set(state.placements)
    assert all(chain.is_whole() for chain in state.chains)
    if break_cost is None:
        assert set(chained) == set(state.placements)
    assert state.revisable() == [placement for placement in state.placements if placement not in set(chained)]
    fresh = Loss.from_config(pipeline.losses["fit"])(chain_task.target, state.construction())
    assert state.selector.value() == pytest.approx(fresh, abs=1e-9)


@pytest.mark.parametrize("gains, longest, expected", [
    ([-0.5, 1, 2, -0.2, 1.5, -np.inf, 5], 10, ((6, 7), 5)),
    ([-0.5, 1, 2, -0.2, 1.5], 10, ((1, 5), 4.3)),
    ([-0.5, 1, 2, -0.2, 1.5], 2, ((1, 3), 3)),
    ([3, -np.inf, 4], 3, ((2, 3), 4)),
    ([np.inf], 1, ((0, 1), np.inf)),
    ([], 2, (None, -np.inf)),
    ([1], 0, (None, -np.inf)),
])
def test_best_run_respects_the_budget_and_rejected_segments(gains, longest, expected):
    run, total = best_run(np.array(gains), longest)
    assert run == expected[0]
    assert total == pytest.approx(expected[1])


@pytest.mark.parametrize("retries", [0, 2])
def test_chain_fill_retries_when_no_chain_helps(chain_task, retries):
    source = OfferedChains()
    state = state_for(chain_task, UncoveredVolumeConfig(grid=GRID), {"empty": source})
    ChainFill(chains=("empty",), retries=retries).run(state)
    assert source.asked == 1 + retries
    assert not state.placements


@pytest.mark.parametrize("room, item_limit, expected", [(8, 2, 2), (2, None, 2), (0, None, 0)])
def test_chain_fill_respects_item_and_stage_limits(chain_task, room, item_limit, expected):
    source = OfferedChains([straight_chain(count=4)])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: -len(placed)), {"chains": source},
                      Scope(loss="fit", max_items=room))
    ChainFill(chains=("chains",), items=item_limit).run(state)
    assert len(state.placements) == expected
    assert source.asked == (0 if not room else 1)


def test_chain_fill_never_joins_across_a_filtered_segment(chain_task):
    chain = straight_chain().relaid(np.array([1.0, 0.5, 1.0]))
    state = state_for(chain_task, ScoreConfig(score=lambda placed: -len(placed)),
                      {"chains": OfferedChains([chain])}, Scope(loss="fit", filters=(SizeRange(smallest=0.15),)))
    ChainFill(chains=("chains",), refresh_every=10).run(state)
    assert state.placements == (chain.placements[0],)
    assert len(state.chains) == 1


def test_chain_fill_counts_every_copy_against_the_budget(chain_task, monkeypatch):
    chain = straight_chain(count=4)
    copy = chain.changed(joints=chain.joints + (0, 0.3, 0))
    group = ChainGroup(chain, copies=(copy,))
    monkeypatch.setattr(ChainFill, "_grouped", lambda self, state, chain: group)
    state = state_for(chain_task, ScoreConfig(score=lambda placed: -len(placed)),
                      {"chains": OfferedChains([chain])})
    ChainFill(chains=("chains",), items=5).run(state)
    assert len(state.placements) == 4
    assert [len(chain) for chain in state.chains] == [2, 2]


def test_trimmed_chain_is_checked_again_without_the_discarded_segments(chain_task):
    chain = straight_chain(count=2)
    first, last = chain.placements
    scores = {frozenset(): 0, frozenset([first]): 1, frozenset([last]): 1, frozenset([first, last]): -10}
    state = state_for(chain_task, ScoreConfig(score=lambda placed: scores[frozenset(placed)]),
                      {"chains": OfferedChains([chain])},
                      Scope(loss="fit", selection=Shortlist(UncoveredVolumeConfig(grid=GRID))))
    ChainFill(chains=("chains",), refresh_every=10).run(state)
    assert state.placements == chain.placements
    assert state.selector.value() == -10


@pytest.mark.parametrize("filtered", [False, True])
def test_whole_chain_moves_obey_stage_filters(chain_task, monkeypatch, filtered):
    chain = straight_chain()
    moved = chain.relaid(np.full(3, 0.5))
    monkeypatch.setattr(ChainMoves, "around", lambda *args: [moved])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: sum(p.scale - 10 for p in placed)),
                      scope=Scope(loss="fit", filters=(SizeRange(smallest=0.2),) if filtered else ()))
    state.add_group(ChainGroup(chain))
    ChainPolish(moves=STILL, rounds=1).run(state)
    assert state.chains == ((chain,) if filtered else (moved,))


@pytest.mark.parametrize("filtered", [False, True])
def test_split_nudges_obey_stage_filters(chain_task, monkeypatch, filtered):
    chain = straight_chain()
    monkeypatch.setattr(Nudges, "around", lambda self, task, p, placed: [Placement(p.item, p.center, p.rotation, 0.5)])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: sum(p.scale - 10 for p in placed)),
                      scope=Scope(loss="fit", filters=(SizeRange(smallest=0.2),) if filtered else ()))
    state.add_group(ChainGroup(chain))
    ChainPolish(moves=STILL, rounds=1, break_cost=0.1).run(state)
    assert bool(state.revisable()) == (not filtered)
    assert len(state.placements) == 3
    assert min(p.scale for p in state.placements) == (1.0 if filtered else 0.5)


@pytest.mark.parametrize("break_cost, split", [(None, False), (0, True), (0.5, True), (1, False)])
def test_breaking_a_chain_requires_the_extra_gain(chain_task, monkeypatch, break_cost, split):
    chain = straight_chain()
    middle = chain.placements[1]
    monkeypatch.setattr(Nudges, "around", lambda *args: [])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: sum(1 if p is middle else -2 for p in placed)))
    state.add_group(ChainGroup(chain))
    ChainPolish(moves=STILL, rounds=1, break_cost=break_cost).run(state)
    assert [len(chain) for chain in state.chains] == ([1, 1] if split else [3])
    assert (middle not in state.placements) == split


@pytest.mark.parametrize("break_cost, split", [(0.25, True), (1, False)])
def test_a_break_must_beat_the_best_whole_move(chain_task, monkeypatch, break_cost, split):
    chain = straight_chain()
    moved = chain.changed(joints=chain.joints + (0, 0.1, 0))
    ends = (chain.placements[0], chain.placements[2])
    scores = {frozenset(chain.placements): -3, frozenset(moved.placements): -4, frozenset(ends): -4.5}
    monkeypatch.setattr(ChainMoves, "around", lambda *args: [moved])
    monkeypatch.setattr(Nudges, "around", lambda *args: [])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: scores.get(frozenset(placed), 0)))
    state.add_group(ChainGroup(chain))
    ChainPolish(moves=STILL, rounds=1, break_cost=break_cost).run(state)
    assert state.placements == (ends if split else moved.placements)


def test_polish_can_delete_a_whole_group_without_paying_for_a_break(chain_task):
    chain = straight_chain()
    copy = chain.changed(joints=chain.joints + (0, 0.3, 0))
    state = state_for(chain_task, ScoreConfig(score=len))
    state.add_group(ChainGroup(chain, copies=(copy,)))
    ChainPolish(moves=STILL, rounds=1, break_cost=100).run(state)
    assert not state.groups and not state.placements
    assert state.selector.value() == 0


def test_chain_fill_can_use_the_budget_freed_by_deleting_a_chain(chain_task):
    old = straight_chain()
    new = old.changed(joints=old.joints + (0, 0.1, 0))
    bad = set(old.placements)
    state = state_for(chain_task, ScoreConfig(score=lambda placed: sum(1 if p in bad else -1 for p in placed)),
                      {"chains": OfferedChains([new])})
    state.add_group(ChainGroup(old))
    ChainPolish(moves=STILL, rounds=1).run(state)
    ChainFill(chains=("chains",), items=3).run(state)
    assert state.placements == new.placements
    assert state.chains == (state.groups[0].primary,)


def test_polish_cannot_grow_a_chain_past_the_stage_budget(chain_task, monkeypatch):
    chain = straight_chain()
    grown = straight_chain(count=4)
    monkeypatch.setattr(ChainMoves, "around", lambda *args: [grown])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: -len(placed)),
                      scope=Scope(loss="fit", max_items=3))
    state.add_group(ChainGroup(chain))
    ChainPolish(moves=STILL, rounds=1).run(state)
    assert state.chains == (chain,)
    assert state.placements == chain.placements


def test_a_group_can_forbid_splitting(chain_task, monkeypatch):
    class UnbrokenGroup(ChainGroup):
        @property
        def may_split(self):
            return False

    chain = straight_chain()
    middle = chain.placements[1]
    monkeypatch.setattr(Nudges, "around", lambda *args: [])
    state = state_for(chain_task, ScoreConfig(score=lambda placed: sum(1 if p is middle else -2 for p in placed)))
    group = UnbrokenGroup(chain)
    state.add_group(group)
    ChainPolish(moves=STILL, rounds=1, break_cost=0).run(state)
    assert state.groups == (group,)
    assert state.placements == chain.placements


def test_plain_refine_and_polish_leave_chain_members_alone(chain_task):
    chain = straight_chain()
    state = state_for(chain_task, ScoreConfig(score=len))
    state.add_group(ChainGroup(chain))
    state.add(Placement(COLUMN, (0, 0, 1), np.eye(3)))
    Polish(moves=Nudges(grid=GRID), rounds=1).run(state)
    Refine().run(state)
    assert state.placements == chain.placements
    assert state.chains == (chain,)


def test_keep_earlier_protects_whole_chain_groups(chain_task):
    state = state_for(chain_task, ScoreConfig(score=len))
    chain = straight_chain()
    state.add_group(ChainGroup(chain))
    Stage(items=ItemSettings(keep_earlier=True), steps=(ChainPolish(moves=STILL, rounds=1),)).run(state)
    assert state.placements == chain.placements
    assert state.chains == (chain,)


def test_one_protected_member_keeps_its_entire_group(chain_task):
    state = state_for(chain_task, ScoreConfig(score=len))
    chain = straight_chain()
    copy = chain.changed(joints=chain.joints + (0, 0.3, 0))
    group = ChainGroup(chain, copies=(copy,))
    state.add_group(group)
    state.use(replace(state.scope, kept=frozenset([copy.placements[1]])))
    ChainPolish(moves=STILL, rounds=1).run(state)
    assert state.groups == (group,)
    assert state.placements == group.placements


def test_trial_scoring_preserves_placement_order_and_the_running_loss(chain_task):
    state = state_for(chain_task, UncoveredVolumeConfig(grid=GRID),
                      scope=Scope(loss="fit", selection=Shortlist(UncoveredSurfaceConfig(grid=GRID))))
    chain = straight_chain()
    state.add_group(ChainGroup(chain))
    other = Placement(COLUMN, (0, 0.1, 0), np.eye(3), 0.5)
    before = state.selector.value()
    state.change_gain([chain.placements[2], chain.placements[0]], [other])
    gains = state.marginal_gains([[other]])
    assert gains[0] == pytest.approx(state.selector.gain(other))
    assert state.placements == chain.placements
    assert state.chains == (chain,)
    assert state.selector.value() == pytest.approx(before)


def test_chain_pipelines_round_trip_through_yaml_and_run(chain_task):
    pipeline = chain_pipeline(break_cost=0.01)
    assert FittingPipeline.from_yaml(pipeline.to_yaml()) == pipeline
    assert FittingPipeline.from_yaml(pipeline.to_yaml(full=True)) == pipeline
    result = pipeline.fit(chain_task, seed=0)
    assert 0 < len(result) <= chain_task.max_items
    chain_task.validate(result)


@pytest.mark.parametrize("step, proposals, message", [
    (ChainFill(chains=("missing",)), {}, "no proposals named 'missing'"),
    (ChainFill(chains=("medial",)), {"medial": MedialChains()}, "runs outside any stage"),
    (ChainPolish(moves=STILL, rounds=1), {}, "runs outside any stage"),
])
def test_pipeline_checks_chain_steps_before_running(step, proposals, message):
    with pytest.raises(ValueError, match=message):
        FittingPipeline(losses={"fit": UncoveredVolumeConfig()}, proposals=proposals, steps=(step,))
