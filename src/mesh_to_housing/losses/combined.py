from math import isnan
from numbers import Real
from typing import Literal

import numpy as np
from pydantic import field_validator

from ..utils.config import Config
from ..utils.values import NonNegativeFloat
from .base import CandidateScorer, Loss, LossConfig, LossSession, implements


class LossTerm(Config):
    loss: "LossConfigs"
    loss_scale: NonNegativeFloat


class CombinedLossConfig(LossConfig):
    """Named loss terms, summed after each is multiplied by its loss scale."""

    type: Literal["combined"] = "combined"
    terms: dict[str, LossTerm]

    @field_validator("terms")
    @classmethod
    def _positive_terms(cls, terms):
        terms = {name: term for name, term in terms.items() if term.loss_scale > 0}
        if not terms:
            raise ValueError("Choose at least one loss term with a positive loss_scale")
        return terms


@implements(CombinedLossConfig)
class CombinedLoss(Loss):
    """A sum of individual losses, each multiplied by its loss scale."""

    def __init__(self, config):
        super().__init__(config)
        self._terms = {name: (term.loss_scale, Loss.from_config(term.loss)) for name, term in config.terms.items()}

    def __call__(self, target, construction):
        values = self.components(target, construction)
        return sum(scale * values[name] for name, (scale, _) in self._terms.items())

    def components(self, target, construction):
        """Evaluate each term once, returning its value before scaling."""
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
        return _ScaledSession([(scale, loss.session(target)) for scale, loss in self._terms.values()])


class _ScaledSession(LossSession):
    def __init__(self, terms):
        self._terms = terms

    def value(self):
        return sum(scale * session.value() for scale, session in self._terms)

    def gain(self, placement):
        return sum(scale * session.gain(placement) for scale, session in self._terms)

    def add(self, placement):
        for _, session in self._terms:
            session.add(placement)

    def remove(self, placement):
        for _, session in self._terms:
            session.remove(placement)

    def scorer(self, placements):
        return _ScaledScorer([(scale, session.scorer(placements)) for scale, session in self._terms])


class _ScaledScorer(CandidateScorer):
    def __init__(self, terms):
        self._terms = terms

    def gains(self):
        total = 0
        for scale, scorer in self._terms:
            total = total + scale * scorer.gains()
        return total
