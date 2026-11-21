from abc import ABC, abstractmethod
from dataclasses import dataclass

from .state import FitState


class SearchStep(ABC):
    @abstractmethod
    def run(self, state: FitState) -> None:
        pass


@dataclass(frozen=True)
class Fill(SearchStep):
    def run(self, state):
        groups = () if state.pool is None else (state.pool,)
        while len(state.placements) < state.budget:
            choice = state.selector.best(groups, state.min_gain)
            if choice is None:
                break
            group, index = choice
            state.add(group.take(index))
