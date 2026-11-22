from abc import ABC, abstractmethod
from typing import Callable, Sequence

import numpy as np
import trimesh

from ..utils.config import Config
from ..construction import Construction
from ..placement import Placement


_IMPLEMENTATIONS: dict[type, type] = {}


def implements(config_class: type) -> Callable[[type], type]:
    """Register the decorated class as the loss to build from configs of config_class."""

    def decorate(loss_class: type) -> type:
        _IMPLEMENTATIONS[config_class] = loss_class
        return loss_class

    return decorate


class LossConfig(Config):
    """The settings of a loss. The loss class is registered separately, with implements."""


class Loss(ABC):
    """How far a construction is from the target. Lower is better."""

    def __init__(self, config: LossConfig):
        self.config = config

    @staticmethod
    def from_config(config: LossConfig) -> "Loss":
        """Build the loss registered for this config's class."""
        if type(config) not in _IMPLEMENTATIONS:
            raise TypeError(f"No loss is registered for {type(config).__name__}")
        return _IMPLEMENTATIONS[type(config)](config)

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
