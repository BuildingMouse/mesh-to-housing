import numpy as np
import trimesh


def prepare_mesh(mesh) -> trimesh.Trimesh:
    """Copy geometry and remove duplicate vertices, degenerate faces and unused vertices."""
    if not isinstance(mesh, trimesh.Trimesh):
        raise TypeError("mesh must be a Trimesh; use MeshLoader.load() to read files or scenes")
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
