from numbers import Integral

import trimesh


def simplify_mesh(mesh: trimesh.Trimesh, face_count: int) -> trimesh.Trimesh:
    """Quadric decimation; the target face count is approximate, with no anchor constraints."""
    if isinstance(face_count, bool) or not isinstance(face_count, Integral) or face_count < 1:
        raise ValueError("face_count must be a positive integer")
    if face_count >= len(mesh.faces):
        return mesh.copy()
    return mesh.simplify_quadric_decimation(face_count=int(face_count))
