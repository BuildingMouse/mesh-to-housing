from pathlib import Path

import numpy as np

from mesh_to_housing import Fill, FittingPipeline
from mesh_to_housing.geometry import item_cells
from tests.perf.profiler import FitProfiler

PIPELINE = FittingPipeline.load(Path(__file__).parent / "pipelines/surface_greedy.yaml")


def test_profiler_records_each_part_without_changing_the_fit(dinosaur):
    plain = PIPELINE.fit(dinosaur, seed=7)
    run, sample = Fill.__dict__["run"], item_cells.sample_occupied
    with FitProfiler() as profiler:
        profiled = PIPELINE.fit(dinosaur, seed=7)

    names = {part.name for _, part in profiler.root.walk()}
    assert {"fit", "stage: fill", "fill", "propose: random_pool", "propose: residual", "score candidates: combined",
            "score candidates: uncovered_surface", "score candidates: excess_surface", "cell index",
            "cells: reach surface", "update gains: uncovered_surface", "add: excess_surface"} <= names
    assert all(part.needs <= profiler.root.peak for _, part in profiler.root.walk())
    assert Fill.__dict__["run"] is run and item_cells.sample_occupied is sample
    assert len(profiled) == len(plain)
    for left, right in zip(profiled, plain):
        assert left.item is right.item
        np.testing.assert_array_equal(left.center, right.center)
