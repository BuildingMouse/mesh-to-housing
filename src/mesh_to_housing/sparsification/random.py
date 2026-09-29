def random_subset(mesh, count, *, candidates, important_points, rng):
    return rng.choice(candidates, size=count, replace=False)
