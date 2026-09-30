from os import PathLike
from pathlib import Path

import numpy as np
import trimesh


class MeshLoader:
    """Read static geometry as a Trimesh."""

    @classmethod
    def load(cls, source) -> trimesh.Trimesh:
        if isinstance(source, trimesh.Trimesh):
            return source.copy()
        if isinstance(source, trimesh.Scene):
            return source.to_mesh()
        if not isinstance(source, (str, PathLike)):
            raise TypeError("source must be a local file path, Trimesh, or Scene")

        path = Path(source).expanduser()
        if not path.is_file():
            raise FileNotFoundError(path)
        file_type = path.suffix.lower().lstrip(".")
        if file_type == "fbx":
            return cls._load_fbx(path)

        if file_type not in trimesh.available_formats():
            raise ValueError(f"Unsupported mesh format: {path.suffix or '(no extension)'}")
        return trimesh.load_scene(path, file_type=file_type, process=False).to_mesh()

    @staticmethod
    def _load_fbx(path):
        import assimp_py

        flags = (assimp_py.Process_Triangulate | assimp_py.Process_PreTransformVertices
                 | assimp_py.Process_SortByPType)
        scene = assimp_py.import_file(str(path), flags)
        meshes = []
        for part in scene.meshes:
            indices = np.array(part.indices, dtype=np.int64)
            if not part.num_faces or indices.size != 3 * part.num_faces:
                continue
            vertices = np.array(part.vertices, dtype=float).reshape(-1, 3)
            meshes.append(trimesh.Trimesh(vertices=vertices, faces=indices.reshape(-1, 3), process=False))
        if not meshes:
            raise ValueError(f"No triangle geometry in {path.name}")
        return trimesh.util.concatenate(meshes)
