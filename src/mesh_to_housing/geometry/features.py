import numpy as np
import trimesh


def normal_variation(mesh: trimesh.Trimesh) -> np.ndarray:
    """Maximum incident dihedral angle, in radians; open edges receive pi."""
    scores = np.zeros(len(mesh.vertices))
    np.maximum.at(
        scores,
        mesh.face_adjacency_edges.ravel(),
        np.repeat(mesh.face_adjacency_angles, 2),
    )
    edges, counts = np.unique(mesh.edges_sorted, axis=0, return_counts=True)
    scores[np.unique(edges[counts == 1])] = np.pi
    return scores
