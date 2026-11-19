from abc import abstractmethod
from dataclasses import dataclass, field

from ...geometry.config import VoxelGridConfig
from ...geometry.volume import VoxelGrid
from ..base import Loss, LossConfig, LossSession


@dataclass(frozen=True)
class VoxelLossConfig(LossConfig):
    grid: VoxelGridConfig = field(default_factory=VoxelGridConfig)


class VoxelLoss(Loss):
    def grid(self, target):
        return VoxelGrid.from_mesh(target, self.config.grid)

    def __call__(self, target, construction):
        session = self.session(target)
        for placement in construction:
            session.add(placement)
        return session.value()

    @abstractmethod
    def session(self, target):
        pass


class _CellUnionSession(LossSession):
    def __init__(self, cells_of_placement, reference_count):
        self._cells_of_placement = cells_of_placement
        self._reference_count = reference_count
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
        self._union |= self._cells(placement)


class CoverageSession(_CellUnionSession):
    """The share of the scored cells that no item covers yet."""

    def value(self):
        return 1.0 - len(self._union) / self._reference_count

    def gain(self, placement):
        return self._new_fraction(placement)


class PenaltySession(_CellUnionSession):
    """Counts the item cells outside the target, as a share of the reference count."""

    def value(self):
        return len(self._union) / self._reference_count

    def gain(self, placement):
        return -self._new_fraction(placement)
