from abc import abstractmethod
from typing import Callable, Iterable, Optional, Sequence
from weakref import WeakKeyDictionary

import numpy as np

from ..geometry.cells import CellHolders, CellKeys, CellWeights
from ..placement import Placement
from .base import CandidateScorer, LossSession

CellsOf = Callable[[Sequence[Placement]], Iterable[CellKeys]]


class CellCounts:
    """How many times each cell was added, with a log of the cells that first appeared or disappeared, and the total
    weight of the cells present. Each cell weighs 1 unless weights are given.
    """

    def __init__(self, weights: Optional[CellWeights] = None):
        self.weights = weights
        self.keys = np.zeros(0, dtype=np.int64)
        self.total = 0.0
        self._counts = np.zeros(0, dtype=np.int64)
        self.changes: list[tuple[CellKeys, int]] = []

    @property
    def repeats(self) -> int:
        return int(self._counts.sum()) - len(self.keys)

    def weight(self, keys: CellKeys) -> float:
        return float(len(keys)) if self.weights is None else float(self.weights(keys).sum())

    def contains(self, keys: CellKeys) -> np.ndarray:
        return _found(self.keys, keys, np.searchsorted(self.keys, keys))

    def add(self, keys: CellKeys) -> None:
        position = np.searchsorted(self.keys, keys)
        found = _found(self.keys, keys, position)
        self._counts[position[found]] += 1
        fresh = keys[~found]
        self.keys = np.insert(self.keys, position[~found], fresh)
        self._counts = np.insert(self._counts, position[~found], 1)
        self.changes.append((fresh, 1))
        self.total += self.weight(fresh)

    def remove(self, keys: CellKeys) -> None:
        self._counts[np.searchsorted(self.keys, keys)] -= 1
        emptied = self._counts == 0
        gone = self.keys[emptied]
        self.changes.append((gone, -1))
        self.total -= self.weight(gone)
        self.keys = self.keys[~emptied]
        self._counts = self._counts[~emptied]


class CellSession(LossSession):
    """Keeps track of the construction's scored cells. Each cell weighs 1 unless weights are given, and the
    reference is the total weight that the scored cells are measured against.
    """

    def __init__(self, cells_of: CellsOf, reference: float, weights: Optional[CellWeights] = None):
        self._cells_of = cells_of
        self._reference = reference
        self._scored = CellCounts(weights)
        # Weak, so candidates that were only scored don't stay alive.
        self._cells_by_placement = WeakKeyDictionary()

    def add(self, placement):
        self._scored.add(self._cells(placement))

    def remove(self, placement):
        self._scored.remove(self._cells(placement))

    def scorer(self, placements):
        return _CellScorer(self, placements)

    @abstractmethod
    def _gains(self, new_weights: np.ndarray, totals: np.ndarray) -> np.ndarray:
        """Score candidates from their new and total cell weights."""

    def _cells(self, placement):
        cells = self._cells_by_placement.get(placement)
        if cells is None:
            cells = self._cells_by_placement[placement] = next(iter(self._cells_of([placement])))
        return cells

    def _new_weight(self, placement):
        keys = self._cells(placement)
        return self._scored.weight(keys[~self._scored.contains(keys)])


class CoverageSession(CellSession):
    """The share of the reference that no placement scores yet, as in uncovered volume or surface."""

    def value(self):
        return 1.0 - self._scored.total / self._reference

    def gain(self, placement):
        return self._new_weight(placement) / self._reference

    def _gains(self, new_weights, totals):
        return new_weights / self._reference


class PenaltySession(CellSession):
    """The weight of the scored cells divided by the reference, as in outside volume or excess surface."""

    def value(self):
        return self._scored.total / self._reference

    def gain(self, placement):
        return -(self._new_weight(placement) / self._reference)

    def _gains(self, new_weights, totals):
        return -(new_weights / self._reference)


class OverlapSession(CellSession):
    """Penalizes each extra placement that scores a cell."""

    def __init__(self, cells_of: CellsOf, reference: float):
        super().__init__(cells_of, reference)

    def value(self):
        return self._scored.repeats / self._reference

    def gain(self, placement):
        return -(len(self._cells(placement)) - self._new_weight(placement)) / self._reference

    def _gains(self, new_weights, totals):
        return -((totals - new_weights) / self._reference)


class _CellScorer(CandidateScorer):
    """Keeps the weight of the new cells each candidate would score, and after each change updates it only for the
    cells that changed.
    """

    def __init__(self, session: CellSession, placements: Sequence[Placement]):
        self._session = session
        scored = session._scored
        self._holders = holders = CellHolders(session._cells_of(placements), len(placements))
        self._totals = holders.totals(scored.weights)
        self._new_weights = self._totals - holders.counts(scored.keys, scored.weights)
        self._seen = len(scored.changes)

    def gains(self):
        scored = self._session._scored
        for keys, step in scored.changes[self._seen:]:
            self._new_weights = self._new_weights - step * self._holders.counts(keys, scored.weights)
        self._seen = len(scored.changes)
        return self._session._gains(self._new_weights, self._totals)


def _found(sorted_keys, keys, position):
    found = np.zeros(len(keys), dtype=bool)
    inside = position < len(sorted_keys)
    found[inside] = sorted_keys[position[inside]] == keys[inside]
    return found
