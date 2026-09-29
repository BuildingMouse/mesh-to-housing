import numpy as np


def farthest_point(mesh, count, *, candidates, important_points, rng):
    points = np.asarray(mesh.vertices)[candidates]
    distances = np.full(len(points), np.inf)
    selected = np.empty(count, dtype=np.int64)

    def update(point):
        delta = points - point
        np.minimum(distances, np.einsum("ij,ij->i", delta, delta), out=distances)

    for point in important_points:
        update(point)

    for i in range(count):
        if i == 0 and not len(important_points):
            index = int(rng.integers(len(points)))
        else:
            index = int(distances.argmax())
        selected[i] = candidates[index]
        update(points[index])
        distances[index] = -np.inf
    return selected
