import numpy as np
import trimesh


def prepare_mesh(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    if not isinstance(mesh, trimesh.Trimesh):
        raise TypeError("mesh must be a trimesh.Trimesh")
    if not len(mesh.vertices) or not np.isfinite(mesh.vertices).all():
        raise ValueError("mesh must contain finite vertices")
    if not len(mesh.faces):
        raise ValueError("mesh must contain triangles")
    if mesh.faces.min() < 0 or mesh.faces.max() >= len(mesh.vertices):
        raise ValueError("mesh contains invalid face indices")

    vertices, inverse = np.unique(mesh.vertices, axis=0, return_inverse=True)
    prepared = trimesh.Trimesh(vertices=vertices, faces=inverse[mesh.faces], process=False)
    prepared.update_faces(prepared.area_faces > 0)
    if not len(prepared.faces):
        raise ValueError("mesh must contain nondegenerate triangles")
    prepared.remove_unreferenced_vertices()
    return prepared


def unique_points(points) -> np.ndarray:
    if points is None:
        return np.empty((0, 3), dtype=float)
    points = np.asarray(points, dtype=float)
    if points.shape == (0,):
        points = points.reshape(0, 3)
    if points.ndim != 2 or points.shape[1] != 3 or not np.isfinite(points).all():
        raise ValueError("important_points must be a finite (N, 3) array")
    _, first = np.unique(points, axis=0, return_index=True)
    return points[np.sort(first)].copy()
