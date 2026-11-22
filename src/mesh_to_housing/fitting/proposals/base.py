from abc import ABC, abstractmethod
from typing import Sequence

import numpy as np

from ...placement import Placement
from ...task import FittingTask


class Proposals(ABC):
    """A source of candidate placements for a construction. Sources keep no state between calls."""

    @abstractmethod
    def propose(self, task: FittingTask, placements: Sequence[Placement], rng: np.random.Generator) -> list[Placement]:
        """Candidates for a construction of these placements."""


def sample_positions(rng: np.random.Generator, available: int, count: int) -> np.ndarray:
    """Up to 'count' of the available positions, picked at random without repeats."""
    return rng.choice(available, min(count, available), replace=False)
