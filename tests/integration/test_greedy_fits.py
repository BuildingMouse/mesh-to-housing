import json
from pathlib import Path

import numpy as np
import pytest

from mesh_to_housing import (
    CombinedLossConfig, ExcessSurfaceConfig, Greedy, Loss, LossSession, LossTerm, OutsideVolumeConfig, RandomPool,
    ResidualProposals, UncoveredSurfaceConfig, UncoveredVolumeConfig, VoxelGridConfig, fit,
)

SNAPSHOTS = Path(__file__).parent / "snapshots/greedy_fits.json"
GRID = VoxelGridConfig(resolution=16)
POOL = RandomPool(GRID, centers=16, orientations=4, scales=2)
RESIDUAL = ResidualProposals(grid=GRID, spots=4, spins=2, scales=2)


def volume_loss():
    return Loss.from_config(CombinedLossConfig({
        "uncovered": LossTerm(UncoveredVolumeConfig(grid=GRID), 1),
        "outside": LossTerm(OutsideVolumeConfig(grid=GRID), 1),
    }))


def surface_loss():
    return Loss.from_config(CombinedLossConfig({
        "uncovered": LossTerm(UncoveredSurfaceConfig(grid=GRID, skin_only=True), 1),
        "excess": LossTerm(ExcessSurfaceConfig(grid=GRID), 1),
    }))


FITS = {
    "volume": (volume_loss, Greedy(pool=POOL)),
    "surface with residual proposals": (surface_loss, Greedy(pool=POOL, renewed=RESIDUAL, renew_every=3)),
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
    loss, algorithm = FITS[name]
    construction = fit(dinosaur, algorithm=algorithm, loss=loss(), seed=7)
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


class _OneByOneLoss(Loss):
    def __init__(self, loss):
        super().__init__(loss.config)
        self._loss = loss

    def __call__(self, target, construction):
        return self._loss(target, construction)

    def session(self, target):
        return _OneByOneSession(self._loss.session(target))


@pytest.mark.parametrize("name", FITS)
def test_batched_scoring_gives_the_same_fit_as_one_by_one(dinosaur, name):
    loss, algorithm = FITS[name]
    batched = fit(dinosaur, algorithm=algorithm, loss=loss(), seed=7)
    one_by_one = fit(dinosaur, algorithm=algorithm, loss=_OneByOneLoss(loss()), seed=7)
    assert len(batched) == len(one_by_one)
    for left, right in zip(batched, one_by_one):
        assert left.item is right.item and left.scale == right.scale
        np.testing.assert_array_equal(left.center, right.center)
        np.testing.assert_array_equal(left.rotation, right.rotation)
