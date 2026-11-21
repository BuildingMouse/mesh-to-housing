import numpy as np


def sample_rotations(count: int, rng: np.random.Generator) -> list[np.ndarray]:
    from scipy.spatial.transform import Rotation

    rotations = [np.eye(3), Rotation.from_euler("x", 90, degrees=True).as_matrix(),
                 Rotation.from_euler("y", 90, degrees=True).as_matrix()][:count]
    if count > 3:
        rotations.extend(Rotation.random(count - 3, random_state=rng).as_matrix())
    return rotations
