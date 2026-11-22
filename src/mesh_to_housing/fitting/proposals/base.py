from abc import ABC, abstractmethod
from typing import Sequence

import numpy as np

from ...placement import Placement
from ...task import FittingTask


class Proposals(ABC):
    @abstractmethod
    def propose(self, task: FittingTask, placements: Sequence[Placement],
                rng: np.random.Generator) -> list[Placement]:
        pass
