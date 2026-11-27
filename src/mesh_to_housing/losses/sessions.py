from math import isnan
from typing import Optional, Sequence

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
    """Works with any loss by evaluating the whole construction, only when its value is asked for. The values of
    the last two constructions are kept, so putting back placements that a trial took out costs nothing.
    """

    def __init__(self, loss: Loss, target: trimesh.Trimesh):
        self._loss = loss
        self._target = target
        self._construction = Construction()
        self._value: Optional[float] = None
        self._recent: list[tuple[frozenset, float]] = []

    def value(self):
        if self._value is None:
            placed = frozenset(self._construction.placements)
            known = [value for placements, value in self._recent if placements == placed]
            if known:
                self._value = known[0]
            else:
                self._value = self._evaluate(self._construction)
                self._recent = [*self._recent[-1:], (placed, self._value)]
        return self._value

    def gain(self, placement):
        current = self.value()
        value = self._evaluate(self._with(placement))
        return 0.0 if value == current else current - value

    def add(self, placement):
        self._construction = self._with(placement)
        self._value = None

    def remove(self, placement):
        placements = list(self._construction.placements)
        del placements[next(index for index, placed in enumerate(placements) if placed is placement)]
        self._construction = Construction(tuple(placements))
        self._value = None

    def _evaluate(self, construction):
        value = float(self._loss(self._target, construction))
        # Reject NaN before it can silently stop the search.
        if isnan(value):
            raise ValueError("Loss returned NaN")
        return value

    def _with(self, placement):
        return Construction((*self._construction.placements, placement))
