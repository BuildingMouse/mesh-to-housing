import numpy as np

from .construction import Construction


def fit(task, *, algorithm, loss, seed=None):
    construction = (algorithm.fit(task, loss, rng=np.random.default_rng(seed))
                    if task.max_items else Construction())
    task.validate(construction)
    return construction
