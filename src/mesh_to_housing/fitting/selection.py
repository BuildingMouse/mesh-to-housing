from abc import ABC, abstractmethod
from typing import Literal, Optional, Sequence

import numpy as np
import trimesh

from ..utils.config import Config
from ..losses.base import CandidateScorer, LossSession
from ..placement import Placement


class Candidates:
    def __init__(self, placements: Sequence[Placement], scorer: CandidateScorer):
        self.placements = tuple(placements)
        self.scorer = scorer
        self.taken = np.zeros(len(self.placements), dtype=bool)

    def __len__(self) -> int:
        return len(self.placements)

    def take(self, index: int) -> Placement:
        self.taken[index] = True
        return self.placements[index]

    def available_gains(self) -> np.ndarray:
        return np.where(self.taken, -np.inf, self.scorer.gains())


class Selector(ABC):
    """Selection state for one fit."""

    @abstractmethod
    def candidates(self, placements: Sequence[Placement]) -> Candidates:
        pass

    @abstractmethod
    def best(self, groups: Sequence[Candidates], min_gain: float) -> Optional[tuple[Candidates, int]]:
        pass

    @abstractmethod
    def gain(self, placement: Placement) -> float:
        pass

    @abstractmethod
    def value(self) -> float:
        pass

    @abstractmethod
    def add(self, placement: Placement) -> None:
        pass

    @abstractmethod
    def remove(self, placement: Placement) -> None:
        pass


class Selection(ABC):
    """Reusable candidate selection policy."""

    @abstractmethod
    def start(self, target: trimesh.Trimesh, session: LossSession) -> Selector:
        pass


class ScoreAll(Config, Selection):
    """Score every candidate with the fitting loss."""

    type: Literal["score_all"] = "score_all"

    def start(self, target, session):
        return _ScoreAllSelector(session)


class _ScoreAllSelector(Selector):
    def __init__(self, session: LossSession):
        self._session = session

    def candidates(self, placements):
        return Candidates(placements, self._session.scorer(placements))

    def best(self, groups, min_gain):
        best, best_gain = None, min_gain
        for group in groups:
            if not len(group):
                continue
            gains = group.available_gains()
            index = int(np.argmax(gains))
            # Preserve proposal order when gains tie.
            if gains[index] > best_gain:
                best, best_gain = (group, index), gains[index]
        return best

    def gain(self, placement):
        return self._session.gain(placement)

    def value(self):
        return self._session.value()

    def add(self, placement):
        self._session.add(placement)

    def remove(self, placement):
        self._session.remove(placement)
