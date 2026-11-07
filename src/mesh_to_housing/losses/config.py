from dataclasses import dataclass
from math import isfinite
from types import MappingProxyType
from typing import Callable, Mapping


@dataclass(frozen=True)
class LossTerm:
    loss: Callable
    weight: float = 1.0

    def __post_init__(self):
        if not callable(self.loss):
            raise TypeError("loss must be callable as loss(target, construction)")
        weight = float(self.weight)
        if not isfinite(weight) or weight < 0:
            raise ValueError("weight must be finite and nonnegative")
        object.__setattr__(self, "weight", weight)


@dataclass(frozen=True)
class LossConfig:
    components: Mapping[str, LossTerm]

    def __post_init__(self):
        components = {}
        for name, term in self.components.items():
            if not isinstance(name, str) or not name.strip():
                raise ValueError("Loss components must have nonempty names")
            if not isinstance(term, LossTerm):
                raise TypeError("Each component must be a LossTerm")
            if term.weight > 0:
                components[name] = term
        if not components:
            raise ValueError("Choose at least one loss component with a positive weight")
        object.__setattr__(self, "components", MappingProxyType(components))
