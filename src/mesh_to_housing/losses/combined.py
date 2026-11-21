from dataclasses import dataclass
from math import isfinite, isnan
from numbers import Real
from types import MappingProxyType
from typing import Mapping

import numpy as np

from .base import CandidateScorer, Loss, LossConfig, LossSession


@dataclass(frozen=True)
class LossTerm:
    config: LossConfig
    weight: float = 1.0

    def __post_init__(self):
        weight = float(self.weight)
        if not isfinite(weight) or weight < 0:
            raise ValueError("weight must be finite and nonnegative")
        object.__setattr__(self, "weight", weight)


@dataclass(frozen=True)
class CombinedLossConfig(LossConfig):
    terms: Mapping[str, LossTerm]

    def __post_init__(self):
        terms = {name: term for name, term in self.terms.items() if term.weight > 0}
        if not terms:
            raise ValueError("Choose at least one loss term with a positive weight")
        object.__setattr__(self, "terms", MappingProxyType(terms))

    def build(self):
        return CombinedLoss(self)


class CombinedLoss(Loss):
    """A weighted sum of individual losses."""

    def __init__(self, config):
        super().__init__(config)
        self._terms = {name: (term.weight, term.config.build()) for name, term in config.terms.items()}

    def __call__(self, target, construction):
        values = self.components(target, construction)
        return sum(weight * values[name] for name, (weight, _) in self._terms.items())

    def components(self, target, construction):
        """Evaluate each term once, returning its unweighted value."""
        values = {}
        for name, (_, loss) in self._terms.items():
            value = loss(target, construction)
            if getattr(value, "ndim", 0) != 0:
                raise ValueError(f"Loss term {name!r} must return a scalar")
            scalar = value.item() if isinstance(value, np.ndarray) else value
            if isinstance(scalar, Real) and isnan(scalar):
                raise ValueError(f"Loss term {name!r} returned NaN")
            values[name] = value
        return values

    def session(self, target):
        return _WeightedSession([(weight, loss.session(target)) for weight, loss in self._terms.values()])


class _WeightedSession(LossSession):
    def __init__(self, terms):
        self._terms = terms

    def value(self):
        return sum(weight * session.value() for weight, session in self._terms)

    def gain(self, placement):
        return sum(weight * session.gain(placement) for weight, session in self._terms)

    def add(self, placement):
        for _, session in self._terms:
            session.add(placement)

    def remove(self, placement):
        for _, session in self._terms:
            session.remove(placement)

    def scorer(self, placements):
        return _WeightedScorer([(weight, session.scorer(placements)) for weight, session in self._terms])


class _WeightedScorer(CandidateScorer):
    def __init__(self, terms):
        self._terms = terms

    def gains(self):
        total = 0
        for weight, scorer in self._terms:
            total = total + weight * scorer.gains()
        return total
