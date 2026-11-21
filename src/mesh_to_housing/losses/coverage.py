from collections import Counter

from .base import LossSession


class _CellUnionSession(LossSession):
    def __init__(self, cells_of_placement, reference_count):
        self._cells_of_placement = cells_of_placement
        self._reference_count = reference_count
        self._counts = Counter()
        self._union = set()
        self._cells_by_placement = {}

    def _cells(self, placement):
        cells = self._cells_by_placement.get(placement)
        if cells is None:
            cells = self._cells_by_placement[placement] = self._cells_of_placement(placement)
        return cells

    def _new_fraction(self, placement):
        return len(self._cells(placement) - self._union) / self._reference_count

    def add(self, placement):
        cells = self._cells(placement)
        self._counts.update(cells)
        self._union.update(cells)

    def remove(self, placement):
        for cell in self._cells(placement):
            count = self._counts[cell] - 1
            if count:
                self._counts[cell] = count
            else:
                del self._counts[cell]
                self._union.remove(cell)


class CoverageSession(_CellUnionSession):
    def value(self):
        return 1.0 - len(self._union) / self._reference_count

    def gain(self, placement):
        return self._new_fraction(placement)


class PenaltySession(_CellUnionSession):
    def value(self):
        return len(self._union) / self._reference_count

    def gain(self, placement):
        return -self._new_fraction(placement)
