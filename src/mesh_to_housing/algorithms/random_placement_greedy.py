from dataclasses import dataclass, field

import numpy as np

from ..construction import Construction
from ..geometry.config import GeometryConfig
from ..geometry.volume import VoxelGrid, occupied_cells
from ..losses.construction_loss import ConstructionLoss
from ..losses.volume import OutsideVolumeLoss, UncoveredVolumeLoss
from ..placement import Placement
from ..validation import positive_integer
from .fitting_algorithm import FittingAlgorithm


@dataclass
class RandomPlacementGreedy(FittingAlgorithm):
    """Choose from a fixed sampled pool, continuing until the budget is filled."""

    geometry: GeometryConfig = field(default_factory=GeometryConfig)
    candidate_centers: int = 256
    scale_count: int = 5
    orientation_count: int = 8

    def __post_init__(self):
        if not isinstance(self.geometry, GeometryConfig):
            raise TypeError("geometry must be a GeometryConfig")
        for name in ("candidate_centers", "scale_count", "orientation_count"):
            positive_integer(getattr(self, name), name)

    def fit(self, task, loss, *, rng):
        state = _GreedySearchState(task, loss, geometry=self.geometry)
        candidates = []
        for placement in _sampled_placements(
            task, state.grid, rng=rng, candidate_centers=self.candidate_centers,
            scale_count=self.scale_count, orientation_count=self.orientation_count,
        ):
            candidate = state.candidate(placement)
            if candidate is not None:
                candidates.append(candidate)
        if len(candidates) < task.max_items:
            raise ValueError("Too few resolved candidates; increase candidate_centers or reduce voxel_pitch")
        for _ in range(task.max_items):
            best = state.choose_best(candidates)
            if best is None:
                break
            index, value = best
            state.accept(candidates.pop(index), value)
        return state.construction


def _sample_rotations(count, rng):
    from scipy.spatial.transform import Rotation

    rotations = [np.eye(3), Rotation.from_euler("x", 90, degrees=True).as_matrix(),
                 Rotation.from_euler("y", 90, degrees=True).as_matrix()][:count]
    if count > 3:
        rotations.extend(Rotation.random(count - 3, random_state=rng).as_matrix())
    return rotations


def _sampled_placements(task, grid, *, rng, candidate_centers, scale_count, orientation_count):
    indices = grid.indices[rng.choice(len(grid.indices), min(candidate_centers, len(grid.indices)), replace=False)]
    centers = grid.origin + indices * grid.pitch
    scales = task.constraints.sample_scales(scale_count)
    rotations = _sample_rotations(orientation_count, rng)
    for center in centers:
        for rotation in rotations:
            for scale in scales:
                for item in task.catalog:
                    yield Placement(item, center, rotation, scale)


@dataclass
class _Candidate:
    placement: object
    inside: frozenset
    outside: frozenset


class _GreedySearchState:
    def __init__(self, task, loss, *, geometry):
        self.construction = Construction()
        self._inside = set()
        self._outside = set()
        self._value = None
        self._loss = lambda construction: float(loss(task.target, construction))
        self._volume_weights = None
        self.grid = VoxelGrid.from_mesh(task.target, pitch=geometry.voxel_pitch, closing=geometry.closing)
        if type(loss) is ConstructionLoss:
            weights = {UncoveredVolumeLoss: 0., OutsideVolumeLoss: 0.}
            for term in loss.config.components.values():
                component = term.loss
                if type(component) not in weights:
                    break
                config = component.config
                pitch = task.target.extents.max() / 96 if config.voxel_pitch is None else config.voxel_pitch
                if self.grid.pitch != pitch or geometry.closing != config.closing:
                    break
                weights[type(component)] += term.weight
            else:
                self._volume_weights = (weights[UncoveredVolumeLoss], weights[OutsideVolumeLoss])

    def candidate(self, placement):
        cells = occupied_cells(self.grid, placement)
        inside = cells & self.grid.cells
        return _Candidate(placement, inside, cells - self.grid.cells) if inside else None

    def evaluate(self, candidate, new_inside, new_outside):
        if self._volume_weights is not None:
            volume_weight, outside_weight = self._volume_weights
            count = len(self.grid.cells)
            gain = (volume_weight * new_inside - outside_weight * new_outside) / count
            value = (volume_weight * (1 - (len(self._inside) + new_inside) / count)
                     + outside_weight * (len(self._outside) + new_outside) / count)
            return gain, value
        if self._value is None:
            self._value = self._loss(self.construction)
        trial = Construction((*self.construction.placements, candidate.placement))
        value = self._loss(trial)
        if np.isnan(value) or np.isnan(self._value):
            raise ValueError("Loss returned NaN")
        if value == self._value and not np.isfinite(value):
            return None
        return self._value - value, value

    def choose_best(self, candidates):
        best, best_score = None, (-np.inf,)
        for index, candidate in enumerate(candidates):
            new_inside = len(candidate.inside - self._inside)
            new_outside = len(candidate.outside - self._outside)
            evaluation = self.evaluate(candidate, new_inside, new_outside)
            if evaluation is None:
                continue
            gain, value = evaluation
            score = (gain, new_inside, -new_outside)
            if score > best_score:
                best, best_score = (index, value), score
        return best

    def accept(self, candidate, value):
        self._inside.update(candidate.inside)
        self._outside.update(candidate.outside)
        self.construction = Construction((*self.construction.placements, candidate.placement))
        self._value = value
