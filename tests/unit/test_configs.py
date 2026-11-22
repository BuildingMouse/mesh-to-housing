"""Reading and writing pipelines as plain data and YAML."""
import pytest

from mesh_to_housing import (
    CandidateSettings, CombinedLossConfig, ConfigError, ExcessSurfaceConfig, Fill, FittingPipeline, ItemSettings,
    LossTerm, Nudges, Polish, RandomPool, Refine, Repeat, ResidualProposals, Shortlist, SizeRange, Stage,
    UncoveredSurfaceConfig, UncoveredVolumeConfig, VoxelGridConfig,
)

GRID = VoxelGridConfig(resolution=64)
SURFACE = CombinedLossConfig({"uncovered": LossTerm(UncoveredSurfaceConfig(grid=GRID, skin_only=True), 4),
                              "excess": LossTerm(ExcessSurfaceConfig(grid=GRID), 1)})


def staged_pipeline():
    return FittingPipeline(
        losses={"coverage": SURFACE},
        proposals={"pool": RandomPool(GRID, centers=128), "residual": ResidualProposals(grid=GRID, spots=16)},
        steps=(
            Stage(name="main shape", minimize="coverage",
                  candidates=CandidateSettings(fixed=("pool",), refreshed=("residual",),
                                               filters=(SizeRange(smallest=0.5),)),
                  items=ItemSettings(budget=0.5, keep_earlier=True), steps=(Fill(),)),
            Repeat(times=4, steps=(Stage(minimize="coverage", candidates=CandidateSettings(refreshed=("residual",)),
                                         steps=(Fill(items=10), Refine(Nudges(), 1))),)),
            Stage(name="finish", minimize="coverage", select=Shortlist(UncoveredVolumeConfig(grid=GRID), size=8),
                  steps=(Polish(Nudges(shift=0.5), 2),)),
        ),
        metrics={"uncovered": UncoveredSurfaceConfig()},
    )


def test_pipelines_read_back_what_they_write():
    pipeline = staged_pipeline()
    text = pipeline.to_yaml()
    assert FittingPipeline.from_yaml(text) == pipeline
    assert FittingPipeline.from_yaml(text).to_yaml() == text
    assert FittingPipeline.from_yaml(pipeline.to_yaml(full=True)) == pipeline


def test_settings_at_their_defaults_are_left_out():
    pipeline = FittingPipeline(losses={"fit": UncoveredVolumeConfig()}, proposals={"pool": RandomPool()},
                               steps=(Stage(minimize="fit", candidates=CandidateSettings(fixed=("pool",)),
                                            steps=(Fill(),)),))
    written = pipeline.to_data()
    assert written["losses"] == {"fit": {"type": "uncovered_volume"}}
    assert written["proposals"] == {"pool": {"type": "random_pool"}}


@pytest.mark.parametrize("text, message", [
    ("losses: {fit: {type: fill}}", r"config\.losses\.fit: Input tag 'fill' .* does not match any of the expected"),
    ("losses: {fit: {grid: {}}}", r"config\.losses\.fit: Unable to extract tag"),
    ("losses: {fit: {type: uncovered_volume, colour: red}}", r"config\.losses\.fit\.colour: Extra inputs"),
    ("losses: {fit: {type: uncovered_volume}}\nsteps: [{stage: fill, minimize: fit, steps: [{type: fill, items: 0}]}]",
     r"config\.steps\[0\]\.steps\[0\]\.items: Input should be greater than 0"),
    ("losses: {fit: {type: uncovered_volume}}\nsteps: [{stage: grow, minimize: fit, pool: random}]",
     r"config\.steps\[0\]\.pool: Extra inputs"),
    ("losses: {fit: {type: uncovered_volume}}\nsteps: [{type: repeat}]", r"config\.steps\[0\]\.times: Field required"),
    ("losses: {fit: {type: uncovered_volume}}\nspeed: fast", r"config\.speed: Extra inputs"),
    ("losses: {fit: {type: uncovered_volume}}\nsteps: [{stage: grow, minimize: nope, steps: [{type: fill}]}]",
     r"config: steps\[0\] \(grow\): no loss named 'nope'"),
])
def test_bad_configs_say_where_they_fail(text, message):
    with pytest.raises(ConfigError, match=message):
        FittingPipeline.from_yaml(text)


def test_pipelines_describe_themselves_as_json_schema():
    definitions = FittingPipeline.model_json_schema()["$defs"]
    assert {"Stage", "Fill", "RandomPool", "CombinedLossConfig"} <= set(definitions)
