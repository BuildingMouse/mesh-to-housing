"""Meshes of items that aren't boxes, shared by the tests."""
import numpy as np
import trimesh


def table_mesh():
    """A table: a top with some thickness on four square legs set in from its corners."""
    parts = [trimesh.creation.box(extents=(2.0, 1.0, 0.15))]
    parts[0].apply_translation((0, 0, 0.725))
    for x in (-0.8, 0.8):
        for y in (-0.3, 0.3):
            parts.append(trimesh.creation.box(extents=(0.15, 0.15, 0.65)))
            parts[-1].apply_translation((x, y, 0.325))
    return trimesh.util.concatenate(parts)


def dome_mesh():
    """Half a ball, flat on its underside."""
    ball = trimesh.creation.icosphere(subdivisions=3, radius=0.5)
    vertices = ball.vertices.copy()
    vertices[:, 2] = np.maximum(vertices[:, 2], 0.0)
    return trimesh.Trimesh(vertices, ball.faces)


def l_mesh():
    """An L of two bars that meet at one end."""
    long, short = trimesh.creation.box(extents=(1.0, 0.3, 0.2)), trimesh.creation.box(extents=(0.3, 0.7, 0.2))
    short.apply_translation((0.35, 0.5, 0.0))
    return trimesh.util.concatenate([long, short])


def flat_top_mesh():
    """A flat square top on a thin round stem, like a mushroom: one flat side over an uneven underside."""
    top = trimesh.creation.box(extents=(1.0, 1.0, 0.15))
    top.apply_translation((0.0, 0.0, 0.6))
    stem = trimesh.creation.cylinder(radius=0.12, height=0.525)
    stem.apply_translation((0.0, 0.0, 0.2625))
    return trimesh.util.concatenate([top, stem])


def taper_mesh():
    """A bar that narrows from one end to the other"""
    square = np.array([(-1, -1), (1, -1), (-1, 1), (1, 1)])
    corners = [(0.0, *corner) for corner in square * 0.15] + [(1.0, *corner) for corner in square * 0.05]
    return trimesh.convex.convex_hull(np.array(corners))
