from typing import Annotated, Union

from pydantic import Field

from .base import ProposalSource
from .chains import ChainSource, MedialChains, SurfaceChains
from .random_pool import RandomPool
from .residual import ResidualProposals

ProposalConfigs = Annotated[
    Union[MedialChains, RandomPool, ResidualProposals, SurfaceChains], Field(discriminator="type"),
]

__all__ = [
    "ChainSource", "MedialChains", "ProposalConfigs", "ProposalSource", "RandomPool", "ResidualProposals",
    "SurfaceChains",
]
