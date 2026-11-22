import json
from pathlib import Path

import numpy as np
import pytest

from mesh_to_housing import FittingPipeline, Loss, LossConfig, LossSession
from mesh_to_housing.losses import LossConfigs, implements

HERE = Path(__file__).parent
SNAPSHOTS = HERE / "snapshots/greedy_fits.json"
FITS = {
    "volume": FittingPipeline.load(HERE / "pipelines/volume_greedy.yaml"),
    "surface with residual proposals": FittingPipeline.load(HERE / "pipelines/surface_greedy.yaml"),
}


def records(construction):
    return [{"item": placement.item.key, "center": placement.center.tolist(),
             "rotation": placement.rotation.tolist(), "scale": placement.scale} for placement in construction]


def save_snapshot(name, saved):
    snapshots = json.loads(SNAPSHOTS.read_text()) if SNAPSHOTS.exists() else {}
    snapshots[name] = saved
    lines = ",\n".join(
        f'  {json.dumps(key)}: [\n' + ",\n".join(f"    {json.dumps(record)}" for record in value) + "\n  ]"
        for key, value in sorted(snapshots.items()))
    SNAPSHOTS.write_text("{\n" + lines + "\n}\n")


@pytest.mark.parametrize("name", FITS)
def test_fit_matches_snapshot(dinosaur, request, name):
    construction = FITS[name].fit(dinosaur, seed=7)
    assert 0 < len(construction) <= dinosaur.max_items
    if request.config.getoption("--update-snapshots"):
        save_snapshot(name, records(construction))
        return
    expected = json.loads(SNAPSHOTS.read_text())[name]
    assert [record["item"] for record in records(construction)] == [record["item"] for record in expected]
    for placement, record in zip(construction, expected):
        np.testing.assert_allclose(placement.center, record["center"], rtol=0, atol=1e-9)
        np.testing.assert_allclose(placement.rotation, record["rotation"], rtol=0, atol=1e-9)
        assert placement.scale == pytest.approx(record["scale"], rel=0, abs=1e-12)


class _OneByOneSession(LossSession):
    """Hides a session's own scorer, so candidates are scored one at a time through gain()."""

    def __init__(self, session):
        self._session = session

    def value(self):
        return self._session.value()

    def gain(self, placement):
        return self._session.gain(placement)

    def add(self, placement):
        self._session.add(placement)

    def remove(self, placement):
        self._session.remove(placement)


class _OneByOneConfig(LossConfig):
    inner: LossConfigs


@implements(_OneByOneConfig)
class _OneByOneLoss(Loss):
    def __init__(self, config):
        super().__init__(config)
        self._loss = Loss.from_config(config.inner)

    def __call__(self, target, construction):
        return self._loss(target, construction)

    def session(self, target):
        return _OneByOneSession(self._loss.session(target))


@pytest.mark.parametrize("name", FITS)
def test_batched_scoring_gives_the_same_fit_as_one_by_one(dinosaur, name):
    plan = FITS[name]
    batched = plan.fit(dinosaur, seed=7)
    one_by_one_losses = {loss: _OneByOneConfig(inner=config) for loss, config in plan.losses.items()}
    # model_copy skips validation, which would reject a loss kind that configs can't name.
    one_by_one = plan.model_copy(update={"losses": one_by_one_losses}).fit(dinosaur, seed=7)
    assert len(batched) == len(one_by_one)
    for left, right in zip(batched, one_by_one):
        assert left.item is right.item and left.scale == right.scale
        np.testing.assert_array_equal(left.center, right.center)
        np.testing.assert_array_equal(left.rotation, right.rotation)
