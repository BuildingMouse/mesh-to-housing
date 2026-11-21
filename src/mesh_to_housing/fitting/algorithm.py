from abc import ABC, abstractmethod

import numpy as np

from ..construction import Construction
from ..fitting_task import FittingTask
from ..losses.base import Loss


class FittingAlgorithm(ABC):
    """A way to search for a construction that lowers a loss."""

    @abstractmethod
    def fit(self, task: FittingTask, loss: Loss, *, rng: np.random.Generator) -> Construction:
        """Return a Construction within the task's budget and transform constraints."""
