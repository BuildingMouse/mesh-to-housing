from abc import ABC, abstractmethod


class FittingAlgorithm(ABC):
    @abstractmethod
    def fit(self, task, loss, *, rng):
        """Return a Construction within the task's budget and transform constraints."""
        pass
