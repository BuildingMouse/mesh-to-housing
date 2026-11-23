"""Time and memory per part of a fit, measured by wrapping the fitting code while a FitProfiler is active."""
import json
import os
import threading
import time
import tracemalloc
from contextlib import contextmanager
from functools import cached_property, wraps
from typing import Callable, Optional, Union

from mesh_to_housing.fitting.filters.base import CandidateFilter
from mesh_to_housing.fitting.moves.base import Moves
from mesh_to_housing.fitting.pipeline import FittingPipeline
from mesh_to_housing.fitting.proposals.base import ProposalSource
from mesh_to_housing.fitting.selection import Selector
from mesh_to_housing.fitting.stage import Repeat, Stage
from mesh_to_housing.fitting.steps import Fill, Polish, Refine
from mesh_to_housing.geometry import item_cells as item_cells_module
from mesh_to_housing.geometry import voxelization
from mesh_to_housing.geometry.cells import CellHolders
from mesh_to_housing.geometry.item_cells import ItemCells
from mesh_to_housing.geometry.surface import TargetSurface
from mesh_to_housing.geometry.voxel_grid import VoxelGrid
from mesh_to_housing.losses.base import CandidateScorer, Loss, LossSession

_MB = 2 ** 20


class Part:
    """One part of the fit at one place in the call tree, with its calls added up."""

    def __init__(self, name: str):
        self.name = name
        self.parts: dict[str, Part] = {}
        self.calls = 0
        self.seconds = 0.0
        self.inner_seconds = 0.0
        self.peak = 0
        self.needs = 0
        self.net = 0
        self.rss = 0

    def part(self, name: str) -> "Part":
        if name not in self.parts:
            self.parts[name] = Part(name)
        return self.parts[name]

    @property
    def own_seconds(self) -> float:
        return self.seconds - self.inner_seconds

    def walk(self, path: tuple[str, ...] = ()):
        """Each part that ran, with the names of the parts leading to it."""
        path = (*path, self.name)
        yield path, self
        for part in self.parts.values():
            if part.seconds or part.calls:
                yield from part.walk(path)

    def to_data(self) -> dict:
        return {"name": self.name, "calls": self.calls, "seconds": self.seconds, "own_seconds": self.own_seconds,
                "peak_mb": self.peak / _MB, "needs_mb": self.needs / _MB, "net_mb": self.net / _MB,
                "rss_mb": self.rss / _MB, "parts": [part.to_data() for part in self.parts.values() if part.seconds or part.calls]}


class _Open:
    def __init__(self, part: Part, started: float, memory: int):
        self.part = part
        self.started = started
        self.memory = memory
        self.peak = memory
        self.rss = 0
        self.discard = False
        self.counted = True


class FitProfiler:
    """Wraps the fitting code while active, so each logical part records its calls, time and memory."""

    def __init__(self, *, trace: bool = True, rss_every: float = 0.005):
        self.trace = trace
        self.root = Part("total")
        self._rss_every = rss_every
        self._open: list[_Open] = []
        self._active: tuple[_Open, ...] = ()
        self._restore: list[Callable[[], None]] = []
        self._stop = threading.Event()
        self._sampler: Optional[threading.Thread] = None

    def __enter__(self) -> "FitProfiler":
        if self.trace:
            tracemalloc.start()
        self._open = [_Open(self.root, time.perf_counter(), self._traced())]
        self._active = tuple(self._open)
        if _rss() is not None:
            self._sampler = threading.Thread(target=self._sample_rss, daemon=True)
            self._sampler.start()
        self._wrap_fitting_code()
        return self

    def __exit__(self, *exc):
        for restore in reversed(self._restore):
            restore()
        self._restore.clear()
        self._stop.set()
        if self._sampler is not None:
            self._sampler.join()
        self._close(self._open[0])
        if self.trace:
            tracemalloc.stop()

    @contextmanager
    def part(self, name: str):
        """Records the code inside as a part of whatever part is running."""
        opened = self._enter(name)
        try:
            yield opened
        finally:
            self._exit(opened)

    def table(self, *, everything: bool = False) -> str:
        """The parts as a tree. Unless everything is set, parts that took under 1% of the time and needed under
        2% of the peak are left out; their time and memory still count in the parts around them.
        """
        rows = [("part", "calls", "total s", "own s", "peak MB", "needs MB", "net MB", "RSS MB")]
        hidden = 0
        for path, part in self.root.walk():
            depth = len(path) - 1
            if not everything and depth and self._small(part):
                hidden += 1
                continue
            memory = (f"{part.peak / _MB:.0f}", f"{part.needs / _MB:.0f}", f"{part.net / _MB:+.0f}") \
                if self.trace else ("-", "-", "-")
            rows.append(("  " * depth + part.name, str(part.calls), f"{part.seconds:.2f}", f"{part.own_seconds:.2f}",
                         *memory, f"{part.rss / _MB:.0f}" if part.rss else "-"))
        widths = [max(len(row[column]) for row in rows) for column in range(len(rows[0]))]
        lines = ["  ".join(cell.ljust(width) if column == 0 else cell.rjust(width)
                           for column, (cell, width) in enumerate(zip(row, widths))) for row in rows]
        if hidden:
            lines.append(f"({hidden} small parts left out)")
        return "\n".join(lines)

    def _small(self, part: Part) -> bool:
        return part.seconds < 0.01 * self.root.seconds and (
            not self.trace or part.needs < 0.02 * self.root.peak)

    def heaviest(self, count: int = 8) -> str:
        """The parts that needed the most memory and the parts that took the most time of their own. For memory,
        a part is left out when one of its own parts needed nearly as much, so each line points at the cause.
        """
        parts = [(path, part) for path, part in self.root.walk() if len(path) > 1]
        lines = []
        if self.trace:
            causes = [(path, part) for path, part in parts
                      if all(inner.needs < 0.9 * part.needs for inner in part.parts.values())]
            lines.append("Most memory needed:")
            for path, part in sorted(causes, key=lambda found: -found[1].needs)[:count]:
                lines.append(f"  {part.needs / _MB:8.0f} MB  {' > '.join(path[1:])}")
        lines.append("Most time of their own:")
        for path, part in sorted(parts, key=lambda found: -found[1].own_seconds)[:count]:
            lines.append(f"  {part.own_seconds:8.2f} s   {' > '.join(path[1:])}")
        return "\n".join(lines)

    def save(self, path: Union[str, os.PathLike]) -> None:
        with open(path, "w") as file:
            json.dump({"traced": self.trace, "parts": self.root.to_data()}, file, indent=1)

    # Measuring

    def _traced(self) -> int:
        return tracemalloc.get_traced_memory()[0] if self.trace else 0

    def _enter(self, name: str) -> _Open:
        outer = self._open[-1]
        if self.trace:
            memory, peak = tracemalloc.get_traced_memory()
            outer.peak = max(outer.peak, peak)
            tracemalloc.reset_peak()
        else:
            memory = 0
        opened = _Open(outer.part.part(name), time.perf_counter(), memory)
        self._open.append(opened)
        self._active = tuple(self._open)
        return opened

    def _exit(self, opened: _Open) -> None:
        assert self._open[-1] is opened, "parts must close in the order they opened"
        self._open.pop()
        self._active = tuple(self._open)
        seconds = self._close(opened)
        outer = self._open[-1]
        outer.part.inner_seconds += seconds
        outer.peak = max(outer.peak, opened.peak)
        outer.rss = max(outer.rss, opened.rss)
        if self.trace:
            tracemalloc.reset_peak()

    def _close(self, opened: _Open) -> float:
        seconds = time.perf_counter() - opened.started
        if self.trace:
            memory, peak = tracemalloc.get_traced_memory()
            opened.peak = max(opened.peak, peak)
        else:
            memory = 0
        if opened.discard:
            return seconds
        part = opened.part
        part.calls += opened.counted
        part.seconds += seconds
        part.peak = max(part.peak, opened.peak)
        part.needs = max(part.needs, opened.peak - opened.memory)
        part.net += memory - opened.memory
        part.rss = max(part.rss, opened.rss)
        return seconds

    def _timed_iteration(self, values, name: str):
        """Yields the values, recording the work of producing them as one call of a part, wherever they are read."""
        iterator, first = iter(values), True
        while True:
            opened = self._enter(name)
            opened.counted, first = first, False
            try:
                value = next(iterator)
            except StopIteration:
                return
            finally:
                self._exit(opened)
            yield value

    def _sample_rss(self) -> None:
        while not self._stop.wait(self._rss_every):
            rss = _rss()
            for opened in self._active:
                if rss > opened.rss:
                    opened.rss = rss

    # Wrapping

    def _wrap_fitting_code(self) -> None:
        self._wrap(FittingPipeline, "fit", "fit")
        self._wrap(FittingPipeline, "evaluate", "metrics")
        self._wrap(Stage, "run", lambda stage, state: f"stage: {stage.name or 'unnamed'}")
        self._wrap(Repeat, "run", lambda repeat, state: f"repeat x{repeat.times}")
        for step, name in ((Fill, "fill"), (Refine, "refine"), (Polish, "polish")):
            self._wrap(step, "run", name)

        self._wrap_cache_misses(voxelization, "voxelize", "voxel grid")
        self._wrap(voxelization, "_surface_voxels", "surface voxels")
        self._wrap_cached(VoxelGrid, "solid_mask", "solid mask")
        self._wrap_cached(VoxelGrid, "_outside_field", "outside distance field")
        self._wrap_cached(VoxelGrid, "_target_tree", "target tree")
        self._wrap_cached(TargetSurface, "mask", "surface mask")
        self._wrap_cached(TargetSurface, "normals", "surface normals")
        self._wrap(TargetSurface, "near", "surface grown by tolerance",
                   when=lambda surface, keys, radius: radius not in surface._near_masks)

        for loss in _defining(Loss, "session"):
            self._wrap(loss, "session", lambda loss, target: f"session: {loss.config.type}", label_result=True)
        for session in _defining(LossSession, "scorer"):
            self._wrap(session, "scorer", lambda session, placements: f"score candidates: {_label(session)}",
                       label_result=True)
        for method in ("add", "remove", "gain"):
            for session in _defining(LossSession, method):
                self._wrap(session, method, lambda session, *_, method=method: f"{method}: {_label(session)}")
        for scorer in _defining(CandidateScorer, "gains"):
            self._wrap(scorer, "gains", lambda scorer: f"update gains: {_label(scorer)}")
        for selector in _defining(Selector, "best"):
            self._wrap(selector, "best", "pick best")
        for source in _defining(ProposalSource, "propose"):
            self._wrap(source, "propose", lambda source, *_: f"propose: {source.type}")
        for moves in _defining(Moves, "around"):
            self._wrap(moves, "around", lambda moves, *_: f"moves: {moves.type}")
        for candidate_filter in _defining(CandidateFilter, "apply"):
            self._wrap(candidate_filter, "apply", lambda candidate_filter, *_: f"filter: {candidate_filter.type}")

        # Cell lists are produced lazily, so most of their work shows up where they are read.
        for method, name in (("occupied_by_each", "cells: occupied"), ("skins_of_each", "cells: skins"),
                             ("reach_each", "cells: reach surface")):
            self._wrap(ItemCells, method, name, lazy=True)
        self._wrap(item_cells_module, "sample_occupied", "sample item cells")
        self._wrap(item_cells_module, "dilate_each", "grow cells")
        self._wrap(CellHolders, "__init__", "cell index")
        self._wrap(CellHolders, "counts", "count holders")

    def _wrap(self, owner, attribute: str, name: Union[str, Callable[..., str]], *,
              when: Optional[Callable[..., bool]] = None, label_result: bool = False, lazy: bool = False) -> None:
        original = owner.__dict__[attribute] if isinstance(owner, type) else getattr(owner, attribute)
        function = original.__func__ if isinstance(original, (classmethod, staticmethod)) else original
        profiler = self

        @wraps(function)
        def wrapper(*args, **kwargs):
            if when is not None and not when(*args, **kwargs):
                return function(*args, **kwargs)
            label = name if isinstance(name, str) else name(*args, **kwargs)
            with profiler.part(label):
                result = function(*args, **kwargs)
            if label_result and result is not None:
                result._profile_label = label.split(": ", 1)[-1]
            return profiler._timed_iteration(result, label) if lazy else result

        replacement = type(original)(wrapper) if isinstance(original, (classmethod, staticmethod)) else wrapper
        setattr(owner, attribute, replacement)
        self._restore.append(lambda: setattr(owner, attribute, original))

    def _wrap_cached(self, owner: type, attribute: str, name: str) -> None:
        cached = owner.__dict__[attribute]
        assert isinstance(cached, cached_property), f"{owner.__name__}.{attribute} is not a cached_property"
        original = cached.func
        profiler = self

        @wraps(original)
        def wrapper(instance):
            with profiler.part(name):
                return original(instance)

        cached.func = wrapper
        self._restore.append(lambda: setattr(cached, "func", original))

    def _wrap_cache_misses(self, module, attribute: str, name: str) -> None:
        """Wraps an lru_cache'd function, keeping only the calls that missed the cache."""
        cached = getattr(module, attribute)
        profiler = self

        @wraps(cached)
        def wrapper(*args, **kwargs):
            misses = cached.cache_info().misses
            with profiler.part(name) as opened:
                result = cached(*args, **kwargs)
                opened.discard = cached.cache_info().misses == misses
            return result

        setattr(module, attribute, wrapper)
        self._restore.append(lambda: setattr(module, attribute, cached))


def _defining(base: type, method: str) -> list[type]:
    """The base and its subclasses that define the method themselves."""
    found, waiting = [], [base]
    while waiting:
        cls = waiting.pop()
        if method in cls.__dict__ and not getattr(cls.__dict__[method], "__isabstractmethod__", False):
            found.append(cls)
        waiting.extend(cls.__subclasses__())
    return found


def _label(value) -> str:
    return getattr(value, "_profile_label", type(value).__name__.lstrip("_"))


def _rss() -> Optional[int]:
    try:
        with open("/proc/self/statm") as file:
            return int(file.read().split()[1]) * os.sysconf("SC_PAGE_SIZE")
    except (OSError, ValueError):
        return None
