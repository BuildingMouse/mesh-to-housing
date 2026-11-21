from abc import abstractmethod
from typing import Callable, Sequence

import numpy as np

from ..geometry.cells import CellKeys, candidate_matrix
from ..placement import Placement
from .base import CandidateScorer, LossSession

CellsOf = Callable[[Sequence[Placement]], list[CellKeys]]


class CellCounts:
    """How many times each cell was added, with a log of the cells that first appeared or disappeared."""

    def __init__(self):
        self.keys = np.zeros(0, dtype=np.int64)
        self._counts = np.zeros(0, dtype=np.int64)
        self.changes: list[tuple[CellKeys, int]] = []

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

    def remove(self, keys: CellKeys) -> None:
        self._counts[np.searchsorted(self.keys, keys)] -= 1
        emptied = self._counts == 0
        self.changes.append((self.keys[emptied], -1))
        self.keys = self.keys[~emptied]
        self._counts = self._counts[~emptied]


class CellSession(LossSession):
    """Keeps track of the construction's scored cells."""

    def __init__(self, cells_of: CellsOf, reference: float):
        self._cells_of = cells_of
        self._reference = reference
        self._scored = CellCounts()
        self._cells_by_placement = {}

    def add(self, placement):
        self._scored.add(self._cells(placement))

    def remove(self, placement):
        self._scored.remove(self._cells(placement))

    def scorer(self, placements):
        return _CellScorer(self, placements)

    @abstractmethod
    def _gains(self, new_counts: np.ndarray) -> np.ndarray:
        """Turn the number of new cells each candidate would score into its gain."""

    def _cells(self, placement):
        cells = self._cells_by_placement.get(placement)
        if cells is None:
            cells = self._cells_by_placement[placement] = self._cells_of([placement])[0]
        return cells

    def _new_count(self, placement):
        keys = self._cells(placement)
        return np.count_nonzero(~self._scored.contains(keys))


class CoverageSession(CellSession):
    """The share of the reference that no placement scores yet, as in uncovered volume or surface."""

    def value(self):
        return 1.0 - len(self._scored.keys) / self._reference

    def gain(self, placement):
        return self._new_count(placement) / self._reference

    def _gains(self, new_counts):
        return new_counts / self._reference


class PenaltySession(CellSession):
    """The scored cells divided by the reference, as in outside volume or excess surface."""

    def value(self):
        return len(self._scored.keys) / self._reference

    def gain(self, placement):
        return -(self._new_count(placement) / self._reference)

    def _gains(self, new_counts):
        return -(new_counts / self._reference)


class _CellScorer(CandidateScorer):
    """Keeps each candidate's number of new scored cells, and after each change updates it only for the cells that
    changed.
    """

    def __init__(self, session: CellSession, placements: Sequence[Placement]):
        self._session = session
        cells = session._cells_of(placements) if placements else []
        self._box, matrix = candidate_matrix(cells)
        if self._box is None:
            self._new_counts = np.zeros(len(cells), dtype=np.int64)
            return
        self._columns = matrix.tocsc()
        unscored = np.ones(self._box.size, dtype=np.int64)
        scored = self._box.numbers(session._scored.keys)
        unscored[scored[scored >= 0]] = 0
        self._new_counts = matrix @ unscored
        self._seen = len(session._scored.changes)

    def gains(self):
        if self._box is not None:
            changes = self._session._scored.changes
            for keys, step in changes[self._seen:]:
                numbers = self._box.numbers(keys)
                numbers = numbers[numbers >= 0]
                if len(numbers):
                    changed = np.asarray(self._columns[:, numbers].sum(axis=1)).ravel()
                    self._new_counts = self._new_counts - step * changed
            self._seen = len(changes)
        return self._session._gains(self._new_counts)


def _found(sorted_keys, keys, position):
    found = np.zeros(len(keys), dtype=bool)
    inside = position < len(sorted_keys)
    found[inside] = sorted_keys[position[inside]] == keys[inside]
    return found
