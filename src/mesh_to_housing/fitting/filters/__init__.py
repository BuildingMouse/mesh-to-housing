from typing import Annotated, Union

from pydantic import Field

from .base import CandidateFilter
from .kinds import ItemKinds
from .size import SizeRange

FilterConfigs = Annotated[Union[ItemKinds, SizeRange], Field(discriminator="type")]

__all__ = ["CandidateFilter", "FilterConfigs", "ItemKinds", "SizeRange"]
