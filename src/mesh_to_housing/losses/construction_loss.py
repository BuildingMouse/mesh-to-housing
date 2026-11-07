from math import isnan
from numbers import Real

import numpy as np

from .config import LossConfig


class ConstructionLoss:
    def __init__(self, config):
        if not isinstance(config, LossConfig):
            raise TypeError("config must be a LossConfig")
        self.config = config

    def __call__(self, target, construction):
        values = self.components(target, construction)
        return sum(term.weight * values[name] for name, term in self.config.components.items())

    def components(self, target, construction):
        """Evaluate each enabled component once, returning its unweighted value."""
        values = {}
        for name, term in self.config.components.items():
            value = term.loss(target, construction)
            if getattr(value, "ndim", 0) != 0:
                raise ValueError(f"Loss component {name!r} must return a scalar")
            scalar = value.item() if isinstance(value, np.ndarray) else value
            if isinstance(scalar, Real) and isnan(scalar):
                raise ValueError(f"Loss component {name!r} returned NaN")
            values[name] = value
        return values
