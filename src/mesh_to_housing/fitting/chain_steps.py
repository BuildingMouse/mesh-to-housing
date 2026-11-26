from typing import Annotated, Literal, Optional, Sequence

import numpy as np
from pydantic import Field

from ..placement import Placement
from ..utils.config import Config
from ..utils.values import NonNegativeFloat, NonNegativeInt, PositiveInt
from .chain import Chain, ChainGroup
from .moves.chains import ChainMoves
from .moves.nudges import Nudges
from .proposals.chains import ChainSource
from .selection import CandidateGroup
from .state import FitState
from .steps import Step


class ChainFill(Config, Step):
    """Adds chains that lower the loss, cutting them to fit the budget.
    Segment scores pick a few chains to measure as a whole.
    """

    type: Literal["chain_fill"] = "chain_fill"
    chains: Annotated[tuple[str, ...], Field(min_length=1)]
    items: Optional[PositiveInt] = None
    shortlist: PositiveInt = 8
    refresh_every: PositiveInt = 1
    retries: NonNegativeInt = 0

    def proposals_used(self):
        return self.chains

    def run(self, state):
        limit = state.budget if self.items is None else min(state.budget, len(state.placements) + self.items)
        if len(state.placements) >= limit:
            return
        sources = [state.proposals_named(name) for name in self.chains]
        offered, retries, added = self._offered(state, sources), self.retries, 0
        while len(state.placements) < limit:
            best = self._best(state, offered, limit - len(state.placements))
            if best is None:
                if not retries:
                    break
                retries -= 1
                offered = self._offered(state, sources)
                continue
            number, group = best
            state.add_group(group)
            offered.take(number)
            added, retries = added + 1, self.retries
            if added % self.refresh_every == 0 and len(state.placements) < limit:
                offered = self._offered(state, sources)

    def _offered(self, state: FitState, sources: Sequence[ChainSource]) -> "_Offered":
        groups = []
        for source in sources:
            for chain in source.propose_chains(state.task, state.placements, state.rng):
                group = self._grouped(state, chain)
                if group is not None:
                    groups.append(group)
        primaries = [placement for group in groups for placement in group.primary.placements]
        return _Offered(groups, state.scored(primaries))

    def _grouped(self, state: FitState, chain: Chain) -> Optional[ChainGroup]:
        return ChainGroup(chain)

    def _best(self, state: FitState, offered: "_Offered", room: int) -> Optional[tuple[int, ChainGroup]]:
        gains = offered.scored.available_gains()
        ranked = []
        for number, (group, start) in enumerate(zip(offered.groups, offered.starts)):
            run, total = best_run(gains[start:start + len(group.primary)], room // len(group.members))
            if run is not None and total > state.min_gain:
                ranked.append((-total * len(group.members), number, run))
        best, best_gain = None, state.min_gain
        for _, number, (start, stop) in sorted(ranked)[:self.shortlist]:
            group = offered.groups[number]
            steps = group.placements_by_segment[start:stop]
            run, _ = best_run(state.marginal_gains(steps), room // len(group.members))
            whole = (0, len(steps))
            for first, last in [whole, *([run] if run is not None and run != whole else [])]:
                trimmed = group.part(start + first, start + last)
                if not state.allows(trimmed.placements):
                    continue
                gain = state.change_gain((), trimmed.placements)
                if gain > best_gain:
                    best, best_gain = (number, trimmed), gain
        return best


class ChainPolish(Config, Step):
    """Adjusts chains as a whole, or removes them when they no longer add anything.
    Deleting a segment from the middle can also break the chain (at an extra cost to only do that if it gains a lot).
    """

    type: Literal["chain_polish"] = "chain_polish"
    moves: ChainMoves
    rounds: NonNegativeInt
    break_cost: Optional[NonNegativeFloat] = None
    nudges: Nudges = Field(default_factory=Nudges)

    def run(self, state):
        for round_number in range(self.rounds):
            factor = 0.5 ** round_number
            moves, nudges = self.moves.finer(factor), self.nudges.finer(factor)
            groups = state.revisable_groups()
            for index in state.rng.permutation(len(groups)):
                self._settle(state, groups[index], moves, nudges)

    def _settle(self, state: FitState, group: ChainGroup, moves: ChainMoves, nudges: Nudges) -> None:
        best, best_gain = None, state.min_gain
        removed_gain = state.change_gain(group.placements, ())
        if removed_gain > best_gain:
            best, best_gain = [], removed_gain
        room = state.budget - len(state.placements)
        for moved in moves.around(state.task, group.primary):
            changed = group.with_primary(moved)
            if changed is None or len(changed.placements) - len(group.placements) > room:
                continue
            removed, added = _difference(group.placements, changed.placements)
            if not state.allows(added):
                continue
            gain = state.change_gain(removed, added)
            if gain > best_gain:
                best, best_gain = [changed], gain
        if self.break_cost is not None and group.may_split:
            split = self._split(state, group, nudges, best_gain if best is not None else 0.0)
            if split is not None:
                state.replace_group(group, *split)
                return
        if best is not None:
            state.replace_group(group, best)

    def _split(self, state: FitState, group: ChainGroup, nudges: Nudges,
               chain_gain: float) -> Optional[tuple[list[ChainGroup], list[Placement]]]:
        best, best_gain = None, chain_gain + self.break_cost + state.min_gain
        segments = group.placements_by_segment
        for index, segment in enumerate(group.primary.placements):
            options = nudges.around(state.task, segment, state.placements)
            # Taking out an end segment only shortens the chain, which its own moves already try.
            middle = 0 < index < len(group.primary) - 1
            for single in [*([None] if middle else []), *options]:
                singles = [] if single is None else group.copies_of(single)
                if not state.allows(singles):
                    continue
                gain = state.change_gain(segments[index], singles)
                if gain > best_gain:
                    best, best_gain = (index, singles), gain
        if best is None:
            return None
        index, singles = best
        count = len(group.primary)
        parts = [group.part(start, stop) for start, stop in ((0, index), (index + 1, count)) if stop > start]
        return parts, singles


class _Offered:
    def __init__(self, groups: list[ChainGroup], scored: CandidateGroup):
        self.groups = groups
        self.scored = scored
        self.starts = np.concatenate(([0], np.cumsum([len(group.primary) for group in groups])))[:-1].astype(int)

    def take(self, number: int) -> None:
        start = self.starts[number]
        self.scored.taken[start:start + len(self.groups[number].primary)] = True


def best_run(gains: np.ndarray, longest: int) -> tuple[Optional[tuple[int, int]], float]:
    best, where = -np.inf, None
    for start in range(len(gains)):
        total = 0.0
        for stop in range(start + 1, min(len(gains), start + longest) + 1):
            if np.isnan(gains[stop - 1]) or gains[stop - 1] == -np.inf:
                break
            total += gains[stop - 1]
            if total > best:
                best, where = total, (start, stop)
    return where, float(best)


def _difference(old: Sequence[Placement], new: Sequence[Placement]) -> tuple[list[Placement], list[Placement]]:
    old_set, new_set = set(old), set(new)
    return ([placement for placement in old if placement not in new_set],
            [placement for placement in new if placement not in old_set])
