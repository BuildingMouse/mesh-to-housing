from pathlib import Path

import numpy as np
import pytest

from mesh_to_housing import MeshLoader, prepare_mesh

DINOSAUR = Path(__file__).resolve().parents[2] / "mesh-assets/dinosaur.dae"


def test_bundled_model_loads_and_prepares():
    mesh = prepare_mesh(MeshLoader.load(DINOSAUR))
    assert (len(mesh.vertices), len(mesh.faces)) == (11153, 22294)
    assert np.isfinite(mesh.vertices).all()
    assert (mesh.extents > 0).all()


def test_unsupported_format_is_rejected(tmp_path):
    path = tmp_path / "model.unknown"
    path.touch()
    with pytest.raises(ValueError, match="Unsupported mesh format: .unknown"):
        MeshLoader.load(path)
