from dataclasses import dataclass

import numpy as np

from .items.item import Item


@dataclass(frozen=True, eq=False)
class Placement:
    item: Item
    center: np.ndarray
    rotation: np.ndarray
    scale: float = 1.0

    @classmethod
    def with_point_at(cls, item, anchor, point, rotation, scale=1.0):
        center = np.asarray(point) - np.asarray(anchor) @ np.asarray(rotation).T * scale
        return cls(item, center, rotation, scale)

    def __post_init__(self):
        center = np.array(self.center, dtype=float, copy=True)
        rotation = np.array(self.rotation, dtype=float, copy=True)
        if center.shape != (3,) or not np.isfinite(center).all():
            raise ValueError("center must contain three finite coordinates")
        if rotation.shape != (3, 3) or not np.isfinite(rotation).all():
            raise ValueError("rotation must be a finite 3x3 matrix")
        if not isinstance(self.item, Item):
            raise TypeError("item must be an Item")
        if not np.isfinite(self.scale) or self.scale <= 0:
            raise ValueError("scale must be finite and positive")
        center.flags.writeable = False
        rotation.flags.writeable = False
        object.__setattr__(self, "center", center)
        object.__setattr__(self, "rotation", rotation)
        object.__setattr__(self, "scale", float(self.scale))

    def validate_rotation(self):
        if not np.allclose(self.rotation.T @ self.rotation, np.eye(3), atol=1e-7, rtol=0) or not np.isclose(
            np.linalg.det(self.rotation), 1.0, atol=1e-7, rtol=0,
        ):
            raise ValueError("rotation must be a proper rotation matrix")

    @property
    def transform(self):
        transform = np.eye(4)
        transform[:3, :3] = self.rotation * self.scale
        transform[:3, 3] = self.center
        return transform

    def world_points(self, points: np.ndarray) -> np.ndarray:
        """Points given in the item's own frame, where the placement puts them."""
        return np.asarray(points) * self.scale @ self.rotation.T + self.center

    @property
    def box_center(self) -> np.ndarray:
        """Where the middle of the item's bounding box lies in the world."""
        return self.center + self.rotation @ self.item.box_center * self.scale
