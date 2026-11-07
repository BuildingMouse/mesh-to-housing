from dataclasses import dataclass, field

from ..geometry.config import GeometryConfig
from ..geometry.volume import VoxelGrid, occupied_cells


@dataclass(frozen=True)
class UncoveredVolumeLoss:
    config: GeometryConfig = field(default_factory=GeometryConfig)

    def __post_init__(self):
        if not isinstance(self.config, GeometryConfig):
            raise TypeError("config must be a GeometryConfig")

    def __call__(self, target, construction):
        return uncovered_volume(target, construction, geometry=self.config)


@dataclass(frozen=True)
class OutsideVolumeLoss:
    config: GeometryConfig = field(default_factory=GeometryConfig)

    def __post_init__(self):
        if not isinstance(self.config, GeometryConfig):
            raise TypeError("config must be a GeometryConfig")

    def __call__(self, target, construction):
        return outside_volume(target, construction, geometry=self.config)


def uncovered_volume(target, construction, *, geometry=None):
    """Uncovered target union volume divided by target volume."""
    return volume_metrics(target, construction, geometry=geometry)["uncovered_fraction"]


def outside_volume(target, construction, *, geometry=None):
    """Outside union volume divided by target volume."""
    return volume_metrics(target, construction, geometry=geometry)["outside_target_fraction"]


def volume_metrics(target, construction, *, geometry=None):
    geometry = GeometryConfig() if geometry is None else geometry
    grid = VoxelGrid.from_mesh(target, pitch=geometry.voxel_pitch, closing=geometry.closing)
    return evaluate_volume(grid, construction)


def evaluate_volume(grid, construction):
    """Union-volume errors; all returned values are fractions."""
    occupied = set()
    for placement in construction:
        occupied.update(occupied_cells(grid, placement))
    if not occupied and len(construction):
        raise ValueError("Construction has no resolved volume; reduce voxel_pitch")
    outside = occupied - grid.cells
    return {
        "outside_fraction": len(outside) / len(occupied) if occupied else 0.0,
        "outside_target_fraction": len(outside) / len(grid.cells),
        "uncovered_fraction": 1.0 - len(occupied & grid.cells) / len(grid.cells),
    }
