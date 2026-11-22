from typing import Annotated, List, Literal, Sequence

import numpy as np
from pydantic import Field

from ...utils.config import Config
from ...utils.values import NonNegativeFloat
from ...geometry.voxel_grid import VoxelGridConfig
from ...placement import Placement
from ...task import FittingTask
from .base import Moves


class Nudges(Config, Moves):
    """Small moves of one placement: shifts along and turns about its own axes, and a slightly larger and
    smaller scale.
    """

    type: Literal["nudges"] = "nudges"
    shift: NonNegativeFloat = 1.0
    turn: NonNegativeFloat = 10.0
    rescale: Annotated[float, Field(ge=1, allow_inf_nan=False)] = 1.15
    grid: VoxelGridConfig = Field(default_factory=VoxelGridConfig)

    def finer(self, factor: float) -> "Nudges":
        return self.model_copy(update=dict(shift=self.shift * factor, turn=self.turn * factor,
                                           rescale=1 + (self.rescale - 1) * factor))

    def around(self, task: FittingTask, placement: Placement, placements: Sequence[Placement] = ()) -> List[Placement]:
        from scipy.spatial.transform import Rotation

        item, rotation, scale = placement.item, placement.rotation, placement.scale
        step = self.shift * self.grid.pitch_for(task.target)
        moves = []
        for axis in range(3):
            for sign in (-1.0, 1.0):
                if step > 0:
                    moves.append(Placement(item, placement.center + sign * step * rotation[:, axis], rotation, scale))
                if self.turn > 0:
                    turn = Rotation.from_rotvec(np.eye(3)[axis] * sign * np.radians(self.turn)).as_matrix()
                    # The turn acts in the item's own frame, so the item turns about its own axis.
                    moves.append(Placement(item, placement.center, rotation @ turn, scale))
        low, high = task.constraints.scale_bounds
        for factor in (self.rescale, 1 / self.rescale):
            rescaled = float(np.clip(scale * factor, low, high))
            if rescaled != scale:
                moves.append(Placement(item, placement.center, rotation, rescaled))
        return moves
