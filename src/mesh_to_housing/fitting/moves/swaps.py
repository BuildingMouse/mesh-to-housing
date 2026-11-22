from typing import Literal

from ...utils.config import Config
from ...placement import Placement
from .base import Moves


class Swaps(Config, Moves):
    """The other catalog items in a placement's spot: same box center, turn and scale."""

    type: Literal["swaps"] = "swaps"

    def finer(self, factor):
        return self

    def around(self, task, placement, placements=()):
        middle = placement.box_center
        return [Placement.with_point_at(item, item.box_center, middle, placement.rotation, placement.scale)
                for item in task.catalog if item is not placement.item]
