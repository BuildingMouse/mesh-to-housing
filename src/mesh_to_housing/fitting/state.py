from dataclasses import dataclass, field, replace
from typing import Mapping, Optional, Sequence

import numpy as np

from ..construction import Construction
from ..losses.base import Loss, LossConfig
from ..placement import Placement
from ..task import FittingTask
from .filters.base import CandidateFilter
from .moves.base import Moves
from .proposals.base import ProposalSource
from .selection import CandidateGroup, ScoreAll, SelectionConfig, Selector


@dataclass(frozen=True)
class Scope:
    """What the steps use at one point in a fit. A stage opens its own scope and puts the outer one back when it
    ends.
    """

    loss: Optional[str] = None
    selection: SelectionConfig = field(default_factory=ScoreAll)
    pools: tuple[CandidateGroup, ...] = ()
    refreshed: tuple[ProposalSource, ...] = ()
    refresh_every: int = 10
    filters: tuple[CandidateFilter, ...] = ()
    max_items: Optional[int] = None
    kept: frozenset[Placement] = frozenset()


class FitState:
    """A fit in progress, shared by the steps. Placements are never changed in place.
    A gain must exceed min_gain, so rounding noise in a sum of loss terms can't add an item.
    """

    def __init__(self, task: FittingTask, rng: np.random.Generator, losses: Mapping[str, LossConfig],
                 proposals: Mapping[str, ProposalSource], scope: Scope, min_gain: float = 1e-12,
                 placements: Sequence[Placement] = ()):
        self.task = task
        self.rng = rng
        self.min_gain = min_gain
        self._loss_configs = losses
        self._built: dict[str, Loss] = {}
        self._proposals = proposals
        self._placements: list[Placement] = list(placements)
        self.scope = scope
        self._selector: Optional[Selector] = None if scope.loss is None else self._start_selector(scope)

    @property
    def selector(self) -> Selector:
        if self._selector is None:
            raise RuntimeError("No loss is set here; set minimize on the enclosing stage")
        return self._selector

    def _loss(self, name: str) -> Loss:
        """The pipeline's loss of that name, built once per fit."""
        if name not in self._built:
            if name not in self._loss_configs:
                raise KeyError(f"The pipeline has no loss named {name!r}")
            self._built[name] = Loss.from_config(self._loss_configs[name])
        return self._built[name]

    def proposals_named(self, name: str) -> ProposalSource:
        if name not in self._proposals:
            raise KeyError(f"The pipeline has no proposals named {name!r}")
        return self._proposals[name]

    def use(self, scope: Scope) -> None:
        """Switch to another scope. A new loss or selection rescores the construction and the pools. A rescored
        pool shares its taken marks with the old one, so no candidate is placed twice.
        """
        if (scope.loss, scope.selection) != (self.scope.loss, self.scope.selection):
            self._selector = None if scope.loss is None else self._start_selector(scope)
            if self._selector is not None:
                scope = replace(scope, pools=tuple(map(self._rescored, scope.pools)))
        if scope.filters != self.scope.filters:
            scope = replace(scope, pools=tuple(self._filtered(pool, scope.filters) for pool in scope.pools))
        self.scope = scope

    def _rescored(self, pool: CandidateGroup) -> CandidateGroup:
        rescored = self.selector.candidates(pool.placements)
        rescored.taken = pool.taken
        rescored.allowed = pool.allowed
        return rescored

    def _filtered(self, pool: CandidateGroup, filters: Sequence[CandidateFilter]) -> CandidateGroup:
        placements = pool.placements
        for candidate_filter in filters:
            placements = candidate_filter.apply(self.task, placements)
        allowed = set(placements)
        filtered = CandidateGroup(pool.placements, pool.scorer)
        filtered.taken = pool.taken
        filtered.allowed = np.array([placement in allowed for placement in pool.placements], dtype=bool)
        return filtered

    def _start_selector(self, scope: Scope) -> Selector:
        session = self._loss(scope.loss).session(self.task.target)
        selector = scope.selection.start(self.task.target, session)
        for placement in self._placements:
            selector.add(placement)
        return selector

    @property
    def placements(self) -> tuple[Placement, ...]:
        return tuple(self._placements)

    @property
    def budget(self) -> int:
        limit = self.scope.max_items
        return self.task.max_items if limit is None else min(limit, self.task.max_items)

    def construction(self) -> Construction:
        return Construction(self.placements)

    def revisable(self) -> list[Placement]:
        """The placements that refine and polish passes may change, in placement order."""
        return [placement for placement in self._placements if placement not in self.scope.kept]

    def candidates(self, placements: Sequence[Placement]) -> CandidateGroup:
        """The placements that pass the filters, as a group the selector can score."""
        for candidate_filter in self.scope.filters:
            placements = candidate_filter.apply(self.task, placements)
        return self.selector.candidates(placements)

    def propose(self, source: ProposalSource) -> CandidateGroup:
        return self.candidates(source.propose(self.task, self.placements, self.rng))

    def propose_refreshed(self) -> list[CandidateGroup]:
        return [self.propose(source) for source in self.scope.refreshed]

    def add(self, placement: Placement, position: Optional[int] = None) -> None:
        self.selector.add(placement)
        self._placements.insert(len(self._placements) if position is None else position, placement)

    def remove(self, placement: Placement) -> int:
        """Take the placement out, and return where it was, so it can be put back in the same place."""
        position = next(index for index, placed in enumerate(self._placements) if placed is placement)
        self.selector.remove(placement)
        del self._placements[position]
        return position

    def replace_with_best_move(self, placement: Placement, moves: Moves) -> Placement:
        """Replace the placement with its best move."""
        position = self.remove(placement)
        group = self.candidates(moves.around(self.task, placement, self.placements))
        choice = self.selector.best([group], self.selector.gain(placement) + self.min_gain)
        placed = placement if choice is None else group.take(choice[1])
        self.add(placed, position)
        return placed
