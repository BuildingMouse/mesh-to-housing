from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import trimesh

from .shapes import Shape


@dataclass
class FittingResult:
    shapes: tuple[Shape, ...] | Shape
    centers: np.ndarray
    rotations: np.ndarray
    scales: np.ndarray
    shape_indices: np.ndarray | None = None

    def __post_init__(self):
        self.shapes = (self.shapes,) if isinstance(self.shapes, Shape) else tuple(self.shapes) # we assume we'll have multiple shapes later
        self.centers = np.array(self.centers, dtype=float, copy=True)
        self.rotations = np.array(self.rotations, dtype=float, copy=True)
        self.scales = np.array(self.scales, dtype=float, copy=True)
        if self.shape_indices is None:
            self.shape_indices = np.zeros(len(self), dtype=int)
        else:
            self.shape_indices = np.array(self.shape_indices, dtype=int, copy=True)

    def __len__(self):
        return len(self.scales)

    @property
    def extents(self):
        """Scaled local bounding-box extents, before rotation."""
        return np.array([shape.extents for shape in self.shapes])[self.shape_indices] * self.scales[:, None]

    @property
    def transforms(self):
        transforms = np.repeat(np.eye(4)[None], len(self), axis=0)
        transforms[:, :3, :3] = self.rotations * self.scales[:, None, None]
        transforms[:, :3, 3] = self.centers
        return transforms

    def to_mesh(self):
        """Concatenate transformed instances."""
        meshes = []
        for index, transform in zip(self.shape_indices, self.transforms):
            mesh = self.shapes[index].mesh.copy()
            mesh.apply_transform(transform)
            meshes.append(mesh)
        return trimesh.util.concatenate(meshes) if meshes else trimesh.Trimesh()
