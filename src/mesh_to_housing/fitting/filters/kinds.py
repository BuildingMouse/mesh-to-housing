from typing import Annotated, Literal

from pydantic import Field

from ...utils.config import Config
from .base import CandidateFilter


class ItemKinds(Config, CandidateFilter):
    """Keeps candidates of the given catalog items, named by their keys."""

    type: Literal["item_kinds"] = "item_kinds"
    keys: Annotated[tuple[str, ...], Field(min_length=1)]

    def apply(self, task, placements):
        return [placement for placement in placements if placement.item.key in self.keys]
