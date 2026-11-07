import json
from pathlib import Path

from .cuboid import Cuboid
from .mesh_item import MeshItem


def load_catalog(path):
    """Load item definitions; mesh paths are relative to the JSON file."""
    path = Path(path).expanduser().resolve()
    definitions = json.loads(path.read_text())
    items = []
    for definition in definitions:
        kind = definition["type"]
        if kind == "cuboid":
            item = Cuboid(definition["key"], tuple(definition["dimensions"]))
        elif kind == "mesh":
            item = MeshItem(
                definition["key"], path.parent / definition["mesh"],
                unit_scale=definition.get("unit_scale", 1.0),
            )
        else:
            raise ValueError(f"Unknown item type: {kind!r}")
        items.append(item)
    if len({item.key for item in items}) != len(items):
        raise ValueError("Catalog item keys must be unique")
    return tuple(items)
