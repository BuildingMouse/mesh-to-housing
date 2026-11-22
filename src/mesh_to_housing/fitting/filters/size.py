from typing import Annotated, Literal

import numpy as np
from pydantic import Field, model_validator

from ...utils.config import Config
from ...utils.values import NonNegativeFloat
from .base import CandidateFilter


class SizeRange(Config, CandidateFilter):
    """Keeps candidates whose width, at their scale, is between smallest and largest, in target units. An item's
    width is the middle side of its bounding box.
    """

    type: Literal["size_range"] = "size_range"
    smallest: NonNegativeFloat = 0.0
    largest: Annotated[float, Field(ge=0)] = float("inf")

    @model_validator(mode="after")
    def _ordered(self):
        if self.smallest > self.largest:
            raise ValueError("smallest must not exceed largest")
        return self

    def apply(self, task, placements):
        return [placement for placement in placements
                if self.smallest <= np.sort(placement.item.box_size)[1] * placement.scale <= self.largest]
