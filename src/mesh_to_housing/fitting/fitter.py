from functools import cached_property
from numbers import Integral

import numpy as np

from ..meshes.loading import MeshLoader
from ..meshes.preparation import prepare_mesh
from ..geometry.volume import VoxelVolume
from .methods import METHODS


class ShapeFitter:
    def __init__(self, mesh, *, volume_pitch=None, closing=0):
        self.mesh = prepare_mesh(MeshLoader.load(mesh))
        self.volume_pitch = float(self.mesh.extents.max() / 96 if volume_pitch is None else volume_pitch)
        self.closing = closing

    @cached_property
    def volume(self):
        return VoxelVolume.from_mesh(self.mesh, pitch=self.volume_pitch, closing=self.closing)

    def fit(self, n_items, *, shape, method="greedy", seed=None, **options):
        if isinstance(n_items, bool) or not isinstance(n_items, Integral) or n_items < 1:
            raise ValueError("n_items must be a positive integer")
        if isinstance(method, str):
            method = METHODS[method]
        result = method(self, n_items, shape, rng=np.random.default_rng(seed), **options)
        assert len(result) == n_items, "Fitting method returned the wrong item count"
        return result
