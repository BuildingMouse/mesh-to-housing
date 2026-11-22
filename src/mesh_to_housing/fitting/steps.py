from abc import ABC, abstractmethod
from typing import Literal, Optional

from ..utils.config import Config
from ..utils.values import NonNegativeInt, PositiveInt
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

