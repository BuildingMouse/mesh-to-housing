from dataclasses import dataclass, field
from numbers import Integral

from .constraints import TransformConstraints
from .items.item import Item
from .meshes.loading import MeshLoader
from .meshes.preparation import prepare_mesh


@dataclass(frozen=True, eq=False)
class FittingTask:
    target: object
    catalog: tuple
    max_items: int
    constraints: TransformConstraints = field(default_factory=TransformConstraints)

    def __post_init__(self):
        catalog = tuple(self.catalog)
        if not catalog or not all(isinstance(item, Item) for item in catalog):
            raise ValueError("catalog must contain at least one Item")
        if len({item.key for item in catalog}) != len(catalog):
            raise ValueError("Catalog item keys must be unique")
        if isinstance(self.max_items, bool) or not isinstance(self.max_items, Integral) or self.max_items < 0:
            raise ValueError("max_items must be a nonnegative integer")
        if not isinstance(self.constraints, TransformConstraints):
            raise TypeError("constraints must be TransformConstraints")
        object.__setattr__(self, "catalog", catalog)
        object.__setattr__(self, "target", prepare_mesh(MeshLoader.load(self.target)))

    def validate(self, construction):
        if len(construction) > self.max_items:
            raise ValueError("Construction exceeds the item budget")
        available = frozenset(self.catalog)
        for placement in construction:
            placement.validate_rotation()
            if placement.item not in available:
                raise ValueError(f"Item {placement.item.key!r} is not in the catalog")
            if not self.constraints.allows(placement):
                raise ValueError("Placement violates transform constraints")
