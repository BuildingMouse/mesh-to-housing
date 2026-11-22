"""Stages, Fill and Repeat, and the checks a pipeline runs when it is made."""
import pytest

from mesh_to_housing import (
    CandidateSettings, Construction, Fill, FittingPipeline, Loss, OutsideVolumeConfig, RandomPool, Refine,
    Repeat, ResidualProposals, ScoreAll, Shortlist, Stage, UncoveredVolumeConfig,
)


SEEN = []


class Record(Fill):
    """A step that notes the scope and placement count each time it runs, instead of filling."""

    def run(self, state):
        scope = state.scope
        SEEN.append((scope.loss, scope.selection, bool(scope.pools), len(state.placements)))


@pytest.fixture(autouse=True)
def seen():
    SEEN.clear()
    return SEEN


@pytest.fixture
def losses(grid_config):
    return {"volume": UncoveredVolumeConfig(grid=grid_config), "outside": OutsideVolumeConfig(grid=grid_config)}


@pytest.fixture
def proposals(grid_config):
    return {"pool": RandomPool(grid_config, centers=6, orientations=2, scales=2)}


POOL = CandidateSettings(fixed=("pool",))


def pipeline(losses, proposals, *steps):
    return FittingPipeline(losses=losses, proposals=proposals, steps=steps)


def test_stages_use_their_settings_and_restore_the_outer_ones(task, losses, proposals, seen):
    record = Record()
    ranked = Shortlist(losses["outside"], size=4)
    inner = Stage(minimize="outside", steps=(record,))
    middle = Stage(select=ranked, candidates=POOL, steps=(record, inner))
    pipeline(losses, proposals, Stage(minimize="volume", steps=(record, middle, record))).fit(task, seed=1)
    assert seen == [("volume", ScoreAll(), False, 0), ("volume", ranked, True, 0),
                           ("outside", ranked, True, 0), ("volume", ScoreAll(), False, 0)]


def test_fill_adds_at_most_its_items(task, losses, proposals):
    fill = Stage(minimize="volume", candidates=POOL, steps=(Fill(items=2),))
    construction = pipeline(losses, proposals, fill).fit(task)
    assert len(construction) == 2


@pytest.mark.parametrize("retries", [0, 2])
def test_fill_asks_refreshed_sources_again_only_as_often_as_its_retries(task, losses, retries, monkeypatch):
    calls = []
    monkeypatch.setattr(ResidualProposals, "propose", lambda self, *arguments: calls.append(1) or [])
    stage = Stage(minimize="volume", candidates=CandidateSettings(refreshed=("residual",)),
                  steps=(Fill(retries=retries),))
    pipeline(losses, {"residual": ResidualProposals()}, stage).fit(task, seed=1)
    assert len(calls) == 1 + retries


def test_repeat_runs_its_steps_the_given_number_of_times(task, losses, proposals, seen):
    repeat = Repeat(times=3, steps=(Fill(items=1), Record()))
    pipeline(losses, proposals, Stage(minimize="volume", candidates=POOL, steps=(repeat,))).fit(task, seed=1)
    assert [count for *_, count in seen] == [1, 2, 3]


def test_switching_losses_keeps_pool_candidates_taken(task, losses, proposals):
    steps = (Fill(items=2), Stage(minimize="outside", steps=(Fill(items=2),)), Fill())
    construction = pipeline(losses, proposals, Stage(minimize="volume", candidates=POOL, steps=steps)).fit(task, seed=1)
    assert len({id(placement) for placement in construction}) == len(construction)


def test_evaluate_reports_each_metric(task, losses, proposals):
    fill = FittingPipeline(losses=losses, proposals=proposals, metrics={"outside": losses["outside"]},
                           steps=(Stage(minimize="volume", candidates=POOL, steps=(Fill(items=2),)),))
    construction = fill.fit(task, seed=1)
    report = fill.evaluate(task, construction)
    assert list(report) == ["outside"] and report.items == 2
    assert report["outside"] == Loss.from_config(losses["outside"])(task.target, construction)


def test_refit_continues_from_a_construction(task, losses, proposals):
    fill = pipeline(losses, proposals, Stage(minimize="volume", candidates=POOL, steps=(Fill(items=2),)))
    first = fill.fit(task, seed=1)
    second = fill.refit(task, first, seed=2)
    assert len(second) == 4 and second.placements[:2] == first.placements


def test_shortlist_refines_without_proposal_sources(task, losses, proposals):
    first = pipeline(losses, proposals, Stage(minimize="volume", candidates=POOL, steps=(Fill(items=1),))).fit(
        task, seed=1,
    )
    refine = pipeline(losses, {}, Stage(minimize="volume", select=Shortlist(losses["volume"]), steps=(Refine(),)))
    construction = refine.refit(task, Construction(first.placements * 2), seed=1)
    assert construction.placements == first.placements


@pytest.mark.parametrize("steps, message", [
    ((Stage(minimize="missing", steps=(Fill(),)),), r"steps\[0\]: no loss named 'missing'"),
    ((Stage(name="fill", minimize="volume", candidates=CandidateSettings(refreshed=("missing",)), steps=(Fill(),)),),
     r"steps\[0\] \(fill\): no proposals named 'missing'"),
    ((Stage(candidates=POOL, steps=(Fill(),)),), r"steps\[0\]\.steps\[0\]: Fill runs outside any stage"),
    ((Fill(),), r"steps\[0\]: Fill runs outside any stage"),
])
def test_pipelines_check_names_and_losses_before_running(losses, proposals, steps, message):
    with pytest.raises(ValueError, match=message):
        pipeline(losses, proposals, *steps)


def test_stages_and_repeats_without_steps_are_allowed(losses, proposals):
    pipeline(losses, proposals, Stage(minimize="volume"), Repeat(times=1), Stage(steps=(Repeat(times=1),)))
