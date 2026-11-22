from abc import ABC, abstractmethod
from typing import Literal, Optional

from ..utils.config import Config
from ..utils.values import NonNegativeInt, PositiveInt
from .moves import MoveConfigs
from .state import FitState


class Step(ABC):
    """One step of a fitting pipeline: an action, a stage or a repeat."""

    @abstractmethod
    def run(self, state: FitState) -> None:
        pass

    def children(self) -> tuple["Step", ...]:
        """The steps this one contains, if any."""
        return ()

    def losses_used(self) -> tuple[str, ...]:
        """The names of the pipeline's losses this step uses itself, not counting the steps inside it."""
        return ()

    def proposals_used(self) -> tuple[str, ...]:
        """The names of the pipeline's proposal sources this step uses itself."""
        return ()

    def needs_loss(self) -> bool:
        """Whether this step scores candidates"""
        return True


class Fill(Config, Step):
    """Adds the best candidate, one at a time, until the budget is used, items have been added, or nothing
    lowers the loss. When nothing does, it asks the refreshed sources for new candidates up to retries more
    times in a row before giving up.
    """

    type: Literal["fill"] = "fill"
    items: Optional[PositiveInt] = None
    retries: NonNegativeInt = 0

    def run(self, state):
        scope = state.scope
        limit = state.budget if self.items is None else min(state.budget, len(state.placements) + self.items)
        if len(state.placements) >= limit:
            return
        refreshed = state.propose_refreshed()
        retries = self.retries
        while len(state.placements) < limit:
            choice = state.selector.best((*scope.pools, *refreshed), state.min_gain)
            if choice is None:
                if not scope.refreshed or not retries:
                    break
                retries -= 1
                refreshed = state.propose_refreshed()
                continue
            group, index = choice
            state.add(group.take(index))
            retries = self.retries
            placed = len(state.placements)
            if scope.refreshed and placed < limit and placed % scope.refresh_every == 0:
                refreshed = state.propose_refreshed()


class Refine(Config, Step):
    """Passes that take out each item in turn and put back whatever helps most: the item itself, one of its
    moves, an unused pool candidate or a new candidate from the refreshed sources. Items that no longer help are
    dropped, and a fill uses the freed budget after each pass. Passes stop once one changes nothing.
    """

    type: Literal["refine"] = "refine"
    moves: Optional[MoveConfigs] = None
    passes: NonNegativeInt = 1

    def run(self, state):
        for _ in range(self.passes):
            changed = self._pass(state)
            Fill().run(state)
            if not changed:
                break

    def _pass(self, state: FitState) -> bool:
        visited = state.revisable()
        changed = False
        refreshed = []
        for number, old in enumerate([visited[index] for index in state.rng.permutation(len(visited))]):
            position = state.remove(old)
            if number % state.scope.refresh_every == 0:
                refreshed = state.propose_refreshed()
            groups = [*state.scope.pools, *refreshed]
            if self.moves is not None:
                groups.append(state.candidates(self.moves.around(state.task, old, state.placements)))
            kept_gain = state.selector.gain(old)
            choice = state.selector.best(groups, max(kept_gain, 0.0) + state.min_gain)
            if choice is not None:
                group, index = choice
                new = group.take(index)
            elif kept_gain > state.min_gain:
                new = old
            else:
                changed = True
                continue
            changed = changed or new is not old
            state.add(new, position)
        return changed


class Polish(Config, Step):
    """Settles items into place in rounds. Each round tries every item's moves and keeps any move that lowers
    the loss. The first round uses the moves as given, and each later round makes them half as big.
    """

    type: Literal["polish"] = "polish"
    moves: MoveConfigs
    rounds: NonNegativeInt

    def run(self, state):
        for round_number in range(self.rounds):
            finer = self.moves.finer(0.5 ** round_number)
            visited = state.revisable()
            for index in state.rng.permutation(len(visited)):
                visited[index] = state.replace_with_best_move(visited[index], finer)
