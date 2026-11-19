from abc import ABC, abstractmethod
from math import isnan

from ..construction import Construction


class LossConfig(ABC):
    @abstractmethod
    def build(self):
        """Create the loss this config describes."""


class Loss(ABC):
    def __init__(self, config):
        self.config = config

    @abstractmethod
    def __call__(self, target, construction):
        pass

    def session(self, target):
        return FullEvaluationSession(self, target)


class LossSession(ABC):
    """Follows a construction as items are added, so a loss can update in small steps."""

    @abstractmethod
    def value(self):
        pass

    @abstractmethod
    def gain(self, placement):
        """How much adding a placement would lower the loss."""

    @abstractmethod
    def add(self, placement):
        pass


class FullEvaluationSession(LossSession):
    """Works with any loss by evaluating the whole construction each time."""

    def __init__(self, loss, target):
        self._loss = loss
        self._target = target
        self._construction = Construction()
        self._value = self._evaluate(self._construction)

    def _evaluate(self, construction):
        value = float(self._loss(self._target, construction))
        if isnan(value):
            raise ValueError("Loss returned NaN")
        return value

    def _with(self, placement):
        return Construction((*self._construction.placements, placement))

    def value(self):
        return self._value

    def gain(self, placement):
        value = self._evaluate(self._with(placement))
        return 0.0 if value == self._value else self._value - value

    def add(self, placement):
        self._construction = self._with(placement)
        self._value = self._evaluate(self._construction)
