import numpy as np

from ...geometry.paths import on_surface
from ...geometry.rotations import rotation_about, side_and_up, unit
from ...geometry.settings import PathSettings
from ...geometry.voxel_grid import VoxelGrid
from ...task import FittingTask
from ...utils.values import NonNegativeInt
from ..chain import Chain
from .base import MoveSizes


class ChainMoves(MoveSizes, PathSettings):
    """Small changes to a whole chain that keep the chain connected"""

    reach: NonNegativeInt = 1
    ends: bool = True

    def around(self, task: FittingTask, chain: Chain) -> list[Chain]:
        moves = []
        step = self.shift * self.grid.pitch_for(task.target)
        if step > 0:
            moves += self._bends(chain, step) + self._shifts(chain, step)
        if self.turn > 0:
            moves += self._turns(chain) + self._rolls(chain)
        if self.rescale > 1:
            moves += self._rescales(task, chain)
        if self.ends:
            moves += self._grown(self.path_voxel_grid(task.target), chain)
            if len(chain) > 1:
                moves += [chain.part(1, len(chain)), chain.part(0, len(chain) - 1)]
        return [move for move in moves if move.is_whole()]

    def _bends(self, chain: Chain, step: float) -> list[Chain]:
        joints = chain.joints
        count = len(joints)
        moves = []
        for joint in range(count):
            along = unit(joints[min(joint + 1, count - 1)] - joints[max(joint - 1, 0)])
            side, up = side_and_up(along, chain.ups[min(joint, len(chain) - 1)] + chain.ups[max(joint - 1, 0)])
            follow = np.clip(1.0 - np.abs(np.arange(count) - joint) / (self.reach + 1), 0.0, 1.0)[:, None]
            for direction in (up, side):
                for sign in (-1.0, 1.0):
                    moves.append(chain.changed(joints=joints + sign * step * follow * direction))
        return moves

    def _shifts(self, chain: Chain, step: float) -> list[Chain]:
        along, side, up = _frame(chain)
        return [chain.changed(joints=chain.joints + sign * step * direction)
                for direction in (along, side, up) for sign in (-1.0, 1.0)]

    def _turns(self, chain: Chain) -> list[Chain]:
        _, side, up = _frame(chain)
        middle = chain.joints.mean(axis=0)
        moves = []
        for axis in (up, side):
            for sign in (-1.0, 1.0):
                turn = rotation_about(axis, sign * np.radians(self.turn))
                moves.append(chain.changed(joints=(chain.joints - middle) @ turn.T + middle, ups=chain.ups @ turn.T))
        return moves

    def _rolls(self, chain: Chain) -> list[Chain]:
        moves = []
        for sign in (-1.0, 1.0):
            ups = np.array([rotation_about(along, sign * np.radians(self.turn)) @ up
                            for along, up in zip(chain.directions, chain.ups)])
            moves.append(chain.changed(ups=ups))
        return moves

    def _rescales(self, task: FittingTask, chain: Chain) -> list[Chain]:
        """Every segment, and each one alone, made bigger and smaller, with the chain laid again to fit."""
        low, high = task.constraints.scale_bounds
        moves = []
        for which in [slice(None), *range(len(chain))] if len(chain) > 1 else [slice(None)]:
            for factor in (self.rescale, 1 / self.rescale):
                scales = chain.scales.copy()
                scales[which] = np.clip(scales[which] * factor, low, high)
                if not np.array_equal(scales, chain.scales):
                    moves.append(chain.relaid(scales))
        return moves

    def _grown(self, grid: VoxelGrid, chain: Chain) -> list[Chain]:
        """The chain with one more segment at either end. It heads between the chain's own direction and the flow."""
        moves = []
        for last in (False, True):
            end = len(chain) - 1 if last else 0
            joint = chain.joints[-1] if last else chain.joints[0]
            outward = chain.directions[end] * (1.0 if last else -1.0)
            flow = grid.flow.direction_at(joint[None])[0]
            heading = unit(outward + (flow if np.dot(flow, outward) >= 0 else -flow))
            span = chain.lengths[end] * (1 - chain.link.overlap)
            new_joint, up = joint + heading * span, chain.ups[end]
            if chain.link.anchor == "outer":
                new_joint, up = on_surface(grid, new_joint)
                new_joint = joint + unit(new_joint - joint) * span
            if last:
                joints, ups = np.vstack((chain.joints, new_joint)), np.vstack((chain.ups, up))
                scales = np.append(chain.scales, chain.scales[end])
            else:
                joints, ups = np.vstack((new_joint, chain.joints)), np.vstack((up, chain.ups))
                scales = np.insert(chain.scales, 0, chain.scales[end])
            moves.append(chain.changed(joints=joints, ups=ups, scales=scales))
        return moves


def _frame(chain: Chain) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The chain's overall direction from end to end, and the side and up directions across it."""
    along = unit(chain.joints[-1] - chain.joints[0])
    side, up = side_and_up(along, chain.ups.sum(axis=0))
    return along, side, up
