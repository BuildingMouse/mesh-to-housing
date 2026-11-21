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
        renewed = state.renew()
        renewed_at = len(state.placements)
        while len(state.placements) < state.budget:
            choice = state.selector.best((*groups, *renewed), state.min_gain)
            if choice is None:
                if not renewed or renewed_at == len(state.placements):
                    break
                renewed, renewed_at = state.renew(), len(state.placements)
                continue
            group, index = choice
            state.add(group.take(index))
            if state.renewed and len(state.placements) < state.budget and len(state.placements) % state.renew_every == 0:
                renewed, renewed_at = state.renew(), len(state.placements)
