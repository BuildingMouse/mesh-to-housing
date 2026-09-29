from __future__ import annotations

from dataclasses import dataclass
from numbers import Integral
from typing import Callable

import numpy as np
import trimesh

from ..geometry.mesh import prepare_mesh, unique_points
from ..sparsification import METHODS


@dataclass
class SparseResult:
    points: np.ndarray
    important_mask: np.ndarray

    def point_cloud(self) -> trimesh.points.PointCloud:
        return trimesh.points.PointCloud(self.points.copy())


class MeshProcessor:
    def __init__(self, mesh: trimesh.Trimesh):
        self.mesh = prepare_mesh(mesh)

    def run(
        self,
        n_points: int,
        method: str | Callable = "random",
        *,
        seed: int | None = None,
        important_points=None,
        **options,
    ) -> SparseResult:
        """Return exactly n_points unique coordinates, including supplied anchors."""
        if isinstance(n_points, bool) or not isinstance(n_points, Integral) or n_points < 0:
            raise ValueError("n_points must be a nonnegative integer")
        if isinstance(method, str):
            if method not in METHODS:
                raise ValueError(f"Unknown method {method!r}; choose from {', '.join(METHODS)}")
            method = METHODS[method]
        if not callable(method):
            raise TypeError("method must be a method name or callable")

        anchors = unique_points(important_points)
        vertices = np.asarray(self.mesh.vertices)
        _, groups = np.unique(np.vstack((vertices, anchors)), axis=0, return_inverse=True)
        candidates = np.flatnonzero(~np.isin(groups[:len(vertices)], groups[len(vertices):]))
        count = n_points - len(anchors)
        if count < 0:
            raise ValueError(f"{len(anchors)} important points exceed the budget of {n_points}")
        if count > len(candidates):
            raise ValueError(f"Requested {n_points} points, but only {len(candidates) + len(anchors)} distinct points are available")

        selected = np.empty(0, dtype=np.int64)
        if count:
            selected = np.asarray(method(
                self.mesh,
                count,
                candidates=candidates,
                important_points=anchors,
                rng=np.random.default_rng(seed),
                **options,
            ))
            if (
                selected.shape != (count,)
                or not np.issubdtype(selected.dtype, np.integer)
                or len(np.unique(selected)) != count
                or not np.isin(selected, candidates).all()
            ):
                raise ValueError("Sparsification method must return exactly count distinct candidate vertex indices")

        points = np.vstack((anchors, vertices[selected]))
        return SparseResult(points, np.arange(n_points) < len(anchors))
