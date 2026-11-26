from abc import ABC, abstractmethod
from typing import Annotated, Sequence

from pydantic import Field

from ...geometry.settings import GridSettings
from ...placement import Placement
from ...task import FittingTask
from ...utils.values import NonNegativeFloat


class Moves(ABC):
    @abstractmethod
    def around(self, task: FittingTask, placement: Placement,
               placements: Sequence[Placement] = ()) -> list[Placement]:
        pass

    @abstractmethod
    def finer(self, factor: float) -> "Moves":
        pass


class MoveSizes(GridSettings):
    """How far one move goes: shifts in cells of the grid, turns in degrees, and rescales by a factor."""

    shift: NonNegativeFloat = 1.0
    turn: NonNegativeFloat = 10.0
    rescale: Annotated[float, Field(ge=1, allow_inf_nan=False)] = 1.15

    def finer(self, factor: float):
        """The same moves made smaller by factor, for later rounds."""
        return self.model_copy(update=dict(shift=self.shift * factor, turn=self.turn * factor,
                                           rescale=1 + (self.rescale - 1) * factor))
