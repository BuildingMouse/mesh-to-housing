"""The session for losses without one of their own, which evaluates the whole construction."""
import numpy as np
import pytest
import trimesh

from mesh_to_housing import Cuboid, Loss, Placement
from mesh_to_housing.losses.sessions import FullEvaluationSession


class CountingLoss(Loss):
    """The sum of the placements' x positions, counting how often it is evaluated."""

    def __init__(self):
        super().__init__(None)
        self.evaluations = 0

    def __call__(self, target, construction):
        self.evaluations += 1
        return float(sum(placement.center[0] for placement in construction))


def placements(count):
    return [Placement(Cuboid("box", (1.0, 1.0, 1.0)), (index + 1.0, 0.0, 0.0), np.eye(3)) for index in range(count)]


def test_values_and_gains_match_a_fresh_evaluation():
    loss, (a, b, c) = CountingLoss(), placements(3)
    session = FullEvaluationSession(loss, trimesh.creation.box())
    session.add(a)
    session.add(b)
    assert session.value() == pytest.approx(3.0)
    assert session.gain(c) == pytest.approx(-3.0)
    session.remove(a)
    assert session.value() == pytest.approx(2.0)


def test_only_asking_for_the_value_evaluates_and_a_trial_put_back_costs_nothing():
    loss, (a, b, c) = CountingLoss(), placements(3)
    session = FullEvaluationSession(loss, trimesh.creation.box())
    session.add(a)
    session.add(b)
    assert loss.evaluations == 0
    before = session.value()
    session.remove(a)
    session.add(c)
    session.value()
    session.remove(c)
    session.add(a)
    assert session.value() == before
    assert loss.evaluations == 2
