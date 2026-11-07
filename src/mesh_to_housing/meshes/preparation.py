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


def resize_mesh(mesh, size, *, axis=None):
    """Uniformly resize a copy to the requested longest side or selected axis."""
    if not np.isfinite(size) or size <= 0:
        raise ValueError("size must be finite and positive")
    if axis is not None and axis not in (0, 1, 2):
        raise ValueError("axis must be 0, 1, 2, or None")
    resized = prepare_mesh(mesh)
    extent = float(resized.extents.max() if axis is None else resized.extents[axis])
    if extent <= 0:
        raise ValueError("Selected mesh extent must be positive")
    resized.apply_scale(size / extent)
    return resized
