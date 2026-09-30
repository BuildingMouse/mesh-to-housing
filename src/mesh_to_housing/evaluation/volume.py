def evaluate_volume(target, result):
    """Voxel estimates of union-volume precision and recall errors"""
    occupied = set()
    for index, center, rotation, scale in zip(result.shape_indices, result.centers,
                                             result.rotations, result.scales):
        occupied.update(target.placed_cells(result.shapes[index], center, rotation, scale))
    if not occupied:
        raise ValueError("Fitting result has no resolved volume; reduce the voxel pitch")
    return {
        "outside_percent": len(occupied - target.cells) / len(occupied),
        "uncovered_percent": len(target.cells - occupied) / len(target.cells),
    }
