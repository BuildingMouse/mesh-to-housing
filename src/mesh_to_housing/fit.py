import numpy as np

from .algorithms.fitting_algorithm import FittingAlgorithm
from .construction import Construction
from .fitting_task import FittingTask


def fit(task, *, algorithm, loss, seed=None):
    if not isinstance(task, FittingTask):
        raise TypeError("task must be a FittingTask")
    if not isinstance(algorithm, FittingAlgorithm):
        raise TypeError("algorithm must inherit from FittingAlgorithm")
    if not callable(loss):
        raise TypeError("loss must be callable as loss(target, construction)")
    construction = (algorithm.fit(task, loss, rng=np.random.default_rng(seed))
                    if task.max_items else Construction())
    if not isinstance(construction, Construction):
        raise TypeError("FittingAlgorithm must return a Construction")
    task.validate(construction)
    return construction
