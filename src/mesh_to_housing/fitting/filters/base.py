from abc import ABC, abstractmethod
from typing import Sequence

from ...placement import Placement
from ...task import FittingTask


class CandidateFilter(ABC):
    @abstractmethod
    def apply(self, task: FittingTask, placements: Sequence[Placement]) -> list[Placement]:
        pass
