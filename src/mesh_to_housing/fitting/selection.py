from abc import ABC, abstractmethod
from typing import Annotated, Literal, Optional, Sequence, Union

import numpy as np
import trimesh
from pydantic import Field

from ..utils.config import Config
from ..utils.values import PositiveInt
from ..losses import LossConfigs
from ..losses.base import CandidateScorer, Loss, LossSession
from ..placement import Placement


class CandidateGroup:
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
    """Picks candidates for one fit, and follows the construction as it changes."""

    @abstractmethod
    def candidates(self, placements: Sequence[Placement]) -> CandidateGroup:
        pass

    @abstractmethod
    def best(self, groups: Sequence[CandidateGroup], min_gain: float) -> Optional[tuple[CandidateGroup, int]]:
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


class SelectionConfig(ABC):
    """Reusable candidate selection policy."""

    @abstractmethod
    def start(self, target: trimesh.Trimesh, session: LossSession) -> Selector:
        pass


class ScoreAll(Config, SelectionConfig):
    """Score every candidate with the fitting loss."""

    type: Literal["score_all"] = "score_all"

    def start(self, target, session):
        return _ScoreAllSelector(session)


class Shortlist(Config, SelectionConfig):
    """Rank candidates with a cheap loss, and score only the best few with the fitting loss."""

    type: Literal["shortlist"] = "shortlist"
    ranking: LossConfigs
    size: PositiveInt = 32

    def start(self, target, session):
        return _ShortlistSelector(session, Loss.from_config(self.ranking).session(target), self.size)


SelectionConfigs = Annotated[Union[ScoreAll, Shortlist], Field(discriminator="type")]


class _ScoreAllSelector(Selector):
    def __init__(self, session: LossSession):
        self._session = session

    def candidates(self, placements):
        return CandidateGroup(placements, self._session.scorer(placements))

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


class _ShortlistSelector(Selector):
    def __init__(self, session: LossSession, ranking: LossSession, size: int):
        self._session = session
        self._ranking = ranking
        self._size = size

    def candidates(self, placements):
        return CandidateGroup(placements, self._ranking.scorer(placements))

    def best(self, groups, min_gain):
        """Walk down the ranking one shortlist at a time, and take the best of the first shortlist that helps."""
        available = [np.flatnonzero(~group.taken) for group in groups]
        ranking = np.concatenate([group.scorer.gains()[indices] for group, indices in zip(groups, available)])
        if not len(ranking):
            return None
        starts = np.cumsum([0] + [len(indices) for indices in available])

        def choice(position):
            which = int(np.searchsorted(starts, position, side="right")) - 1
            return groups[which], int(available[which][position - starts[which]])

        order = np.argsort(-ranking, kind="stable")
        for start in range(0, len(order), self._size):
            shortlist = [choice(position) for position in order[start:start + self._size]]
            gains = [self._session.gain(group.placements[index]) for group, index in shortlist]
            best = int(np.argmax(gains))
            if gains[best] > min_gain:
                return shortlist[best]
        return None

    def gain(self, placement):
        return self._session.gain(placement)

    def value(self):
        return self._session.value()

    def add(self, placement):
        self._session.add(placement)
        self._ranking.add(placement)

    def remove(self, placement):
        self._session.remove(placement)
        self._ranking.remove(placement)
