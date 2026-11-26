from typing import Literal, Optional

from ....geometry.cells import select_keys
from ....utils.values import PositiveFloat
from ...base import IncrementalLoss, implements
from ...cell_sessions import OverlapSession
from ..base import VoxelLossConfig


class ItemOverlapConfig(VoxelLossConfig):
    type: Literal["item_overlap"] = "item_overlap"
    shell: Optional[PositiveFloat] = None


@implements(ItemOverlapConfig)
class ItemOverlapLoss(IncrementalLoss):
    """Overlap near and outside the target"""

    def session(self, target):
        grid = self.config.voxel_grid(target)
        shell = 1.0 if self.config.shell is None else self.config.shell / grid.pitch

        def near_outside(placements):
            return select_keys(grid.item_cells.occupied_by_each(placements), lambda keys: grid.depth_of(keys) <= shell)

        return OverlapSession(near_outside, reference=len(grid.surface))
