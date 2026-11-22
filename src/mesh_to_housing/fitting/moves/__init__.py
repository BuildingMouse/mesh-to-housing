from typing import Annotated, Union

from pydantic import Field

from .base import Moves
from .nudges import Nudges
from .swaps import Swaps

MoveConfigs = Annotated[Union[Nudges, Swaps], Field(discriminator="type")]

__all__ = ["MoveConfigs", "Moves", "Nudges", "Swaps"]
