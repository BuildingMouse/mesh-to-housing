from dataclasses import dataclass, field
from typing import Optional, Sequence

import numpy as np

from ..construction import Construction
from ..placement import Placement
from ..task import FittingTask
from .proposals.base import Proposals
from .selection import Candidates, Selector


@dataclass
class FitState:
    task: FittingTask
    selector: Selector
    rng: np.random.Generator
    min_gain: float = 1e-12
    pool: Optional[Candidates] = None
    renewed: tuple[Proposals, ...] = ()
    renew_every: int = 10
    _placements: list[Placement] = field(default_factory=list, init=False, repr=False)

    @classmethod
    def start(cls, task, selection, loss, rng, *, min_gain=1e-12, renewed=(), renew_every=10):
        return cls(task, selection.start(task.target, loss.session(task.target)), rng, min_gain=min_gain,
                   renewed=renewed, renew_every=renew_every)

    @property
    def placements(self) -> tuple[Placement, ...]:
        return tuple(self._placements)

    @property
    def budget(self) -> int:
        return self.task.max_items

    def construction(self) -> Construction:
        return Construction(self.placements)

    def candidates(self, placements: Sequence[Placement]) -> Candidates:
        return self.selector.candidates(placements)

    def propose_pool(self, source) -> None:
        self.pool = self.candidates(source.propose(self.task, self.placements, self.rng))

    def renew(self) -> list[Candidates]:
        return [self.candidates(source.propose(self.task, self.placements, self.rng)) for source in self.renewed]

    def add(self, placement: Placement, position: Optional[int] = None) -> None:
        self.selector.add(placement)
        self._placements.insert(len(self._placements) if position is None else position, placement)

    def remove(self, placement: Placement) -> int:
        position = next(index for index, placed in enumerate(self._placements) if placed is placement)
        self.selector.remove(placement)
        del self._placements[position]
        return position
