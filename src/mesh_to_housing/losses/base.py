from abc import ABC, abstractmethod
from typing import Sequence

import numpy as np
import trimesh

from ..construction import Construction
from ..placement import Placement


class LossConfig(ABC):
    @abstractmethod
    def build(self) -> "Loss":
        """Create the loss this config describes."""


class Loss(ABC):
    """How far a construction is from the target. Lower is better."""

    def __init__(self, config: LossConfig):
        self.config = config

    @abstractmethod
    def __call__(self, target: trimesh.Trimesh, construction: Construction) -> float:
        pass

    def session(self, target: trimesh.Trimesh) -> "LossSession":
        from .sessions import FullEvaluationSession

        return FullEvaluationSession(self, target)


class IncrementalLoss(Loss):
    def __call__(self, target, construction):
        session = self.session(target)
        for placement in construction:
            session.add(placement)
        return session.value()

    @abstractmethod
    def session(self, target):
        pass


class LossSession(ABC):
    """Mutable scoring state for one construction."""

    @abstractmethod
    def value(self) -> float:
        pass

    @abstractmethod
    def gain(self, placement: Placement) -> float:
        """How much adding a placement would lower the loss."""

    @abstractmethod
    def add(self, placement: Placement) -> None:
        pass

    @abstractmethod
    def remove(self, placement: Placement) -> None:
        pass

    def scorer(self, placements: Sequence[Placement]) -> "CandidateScorer":
        from .sessions import OneByOneScorer

        return OneByOneScorer(self, placements)


class CandidateScorer(ABC):
    @abstractmethod
    def gains(self) -> np.ndarray:
        pass
