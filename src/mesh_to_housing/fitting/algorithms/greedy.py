from dataclasses import dataclass, field
from math import isfinite
from typing import Optional

from ...validation import positive_integer
from ..algorithm import FittingAlgorithm
from ..proposals import Proposals, RandomPool
from ..selection import ScoreAll, Selection
from ..state import FitState
from ..steps import Fill


@dataclass(frozen=True)
class Greedy(FittingAlgorithm):
    pool: Optional[Proposals] = field(default_factory=RandomPool)
    selection: Selection = field(default_factory=ScoreAll)
    min_gain: float = 1e-12
    renewed: Optional[Proposals] = None
    renew_every: int = 10

    def __post_init__(self):
        positive_integer(self.renew_every, "renew_every")
        if not isfinite(self.min_gain) or self.min_gain < 0:
            raise ValueError("min_gain must be finite and nonnegative")

    def fit(self, task, loss, *, rng):
        state = self.start(task, loss, rng)
        Fill().run(state)
        return state.construction()

    def start(self, task, loss, rng):
        sources = () if self.renewed is None else (self.renewed,)
        state = FitState.start(task, self.selection, loss, rng, min_gain=self.min_gain,
                               renewed=sources, renew_every=self.renew_every)
        if self.pool is not None:
            state.propose_pool(self.pool)
        return state
