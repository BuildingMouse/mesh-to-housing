from pathlib import Path

import pytest

from mesh_to_housing import Cuboid, FittingTask, TransformConstraints

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def dinosaur():
    catalog = (Cuboid("tile", (2.0, 2.0, 0.43)), Cuboid("column", (0.43, 0.43, 2.0)))
    return FittingTask(ROOT / "mesh-assets/dinosaur.dae", catalog, 8, TransformConstraints(scale_bounds=(0.5, 1.5)))
