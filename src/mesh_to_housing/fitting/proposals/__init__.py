from typing import Annotated, Union

from pydantic import Field

from .base import ProposalSource
from .random_pool import RandomPool
from .residual import ResidualProposals

ProposalConfigs = Annotated[Union[RandomPool, ResidualProposals], Field(discriminator="type")]

__all__ = ["ProposalConfigs", "ProposalSource", "RandomPool", "ResidualProposals"]
