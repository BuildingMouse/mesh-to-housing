import numpy as np


def rotation_about(axis: np.ndarray, angle: float) -> np.ndarray:
    from scipy.spatial.transform import Rotation

    return Rotation.from_rotvec(axis * angle).as_matrix()


def rotation_onto(axis: np.ndarray, direction: np.ndarray) -> np.ndarray:
    from scipy.spatial.transform import Rotation

    cross = np.cross(axis, direction)
    sine, cosine = np.linalg.norm(cross), float(np.dot(axis, direction))
    if sine > 1e-9:
        return Rotation.from_rotvec(cross / sine * np.arctan2(sine, cosine)).as_matrix()
    if cosine > 0:
        return np.eye(3)
    # Opposite vectors need a half turn around a perpendicular axis.
    perpendicular = np.cross(axis, np.eye(3)[np.argmin(np.abs(axis))])
    return Rotation.from_rotvec(np.pi * perpendicular / np.linalg.norm(perpendicular)).as_matrix()


def random_rotations(count: int, rng: np.random.Generator) -> np.ndarray:
    from scipy.spatial.transform import Rotation

    return Rotation.random(count, random_state=rng).as_matrix()


def sample_rotations(count: int, rng: np.random.Generator) -> list[np.ndarray]:
    from scipy.spatial.transform import Rotation

    rotations = [np.eye(3), Rotation.from_euler("x", 90, degrees=True).as_matrix(),
                 Rotation.from_euler("y", 90, degrees=True).as_matrix()][:count]
    if count > 3:
        rotations.extend(Rotation.random(count - 3, random_state=rng).as_matrix())
    return rotations
