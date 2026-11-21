from math import isnan
from typing import Sequence

import numpy as np
import trimesh

from ..construction import Construction
from ..placement import Placement
from .base import CandidateScorer, Loss, LossSession


class OneByOneScorer(CandidateScorer):
    def __init__(self, session: LossSession, placements: Sequence[Placement]):
        self._session = session
        self._placements = list(placements)

    def gains(self):
        return np.array([self._session.gain(placement) for placement in self._placements], dtype=float)


class FullEvaluationSession(LossSession):
    """Works with any loss by evaluating the whole construction each time."""

    def __init__(self, loss: Loss, target: trimesh.Trimesh):
        self._loss = loss
        self._target = target
        self._construction = Construction()
        self._value = self._evaluate(self._construction)

    def value(self):
        return self._value

    def gain(self, placement):
        value = self._evaluate(self._with(placement))
        return 0.0 if value == self._value else self._value - value

    def add(self, placement):
        self._construction = self._with(placement)
        self._value = self._evaluate(self._construction)

    def remove(self, placement):
        placements = list(self._construction.placements)
        del placements[next(index for index, placed in enumerate(placements) if placed is placement)]
        self._construction = Construction(tuple(placements))
        self._value = self._evaluate(self._construction)

    def _evaluate(self, construction):
        value = float(self._loss(self._target, construction))
        # Reject NaN before it can silently stop the search.
        if isnan(value):
            raise ValueError("Loss returned NaN")
        return value

    def _with(self, placement):
        return Construction((*self._construction.placements, placement))
