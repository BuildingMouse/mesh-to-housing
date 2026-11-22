from abc import ABC, abstractmethod
from typing import Sequence

from ...placement import Placement
from ...task import FittingTask


class Moves(ABC):
    @abstractmethod
    def around(self, task: FittingTask, placement: Placement,
               placements: Sequence[Placement] = ()) -> list[Placement]:
        pass

    @abstractmethod
    def finer(self, factor: float) -> "Moves":
        pass
