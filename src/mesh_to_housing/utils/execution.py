import atexit
from contextvars import ContextVar
from math import ceil
import multiprocessing

from .values import positive_integer


class Shared:
    def __init__(self, index: int):
        self.index = index

    def get(self):
        return current_execution()._shared[self.index]


class Execution:
    """The worker processes, and the geometry they share, for code run inside one `with Execution(...)` block."""

    def __init__(self, workers: int = 1):
        positive_integer(workers, "workers")
        self.workers = workers
        self._pool = None
        self._shared = []
        self._shared_at_fork = 0
        self._tokens = []

    def __enter__(self):
        self._tokens.append(_current.set(self))
        return self

    def __exit__(self, *exc):
        _current.reset(self._tokens.pop())
        if not self._tokens:
            self.close()

    def share(self, value):
        for index, held in enumerate(self._shared):
            if held is value:
                return Shared(index)
        self._shared.append(value)
        return Shared(len(self._shared) - 1)

    def map_chunks(self, function, items, *arguments, minimum=8):
        items = list(items)
        if self.workers <= 1 or len(items) < minimum:
            return function(items, *arguments)
        size = ceil(len(items) / (2 * self.workers))
        chunks = [items[start:start + size] for start in range(0, len(items), size)]
        if self._pool is None or self._shared_at_fork < len(self._shared):
            self._close_pool()
            # Forked workers share the prepared grids instead of receiving a copy with every batch.
            self._pool = multiprocessing.get_context("fork").Pool(
                self.workers, initializer=_enter_in_worker, initargs=(self,))
            self._shared_at_fork = len(self._shared)
        results = self._pool.starmap(_run_chunk, [(function, chunk, arguments) for chunk in chunks])
        return [value for result in results for value in result]

    def _close_pool(self):
        if self._pool is not None:
            self._pool.close()
            self._pool.join()
            self._pool = None

    def close(self):
        self._close_pool()
        self._shared.clear()


def _run_chunk(function, chunk, arguments):
    return function(chunk, *arguments)


def _enter_in_worker(execution):
    _current.set(execution)


_default = Execution()
_current = ContextVar("mesh_to_housing_execution", default=None)
atexit.register(lambda: _default.close())


def current_execution() -> Execution:
    selected = _current.get()
    return _default if selected is None else selected


def map_chunks(function, items, *arguments, minimum=8):
    return current_execution().map_chunks(function, items, *arguments, minimum=minimum)


def share(value):
    return current_execution().share(value)


def worker_count() -> int:
    return current_execution().workers
