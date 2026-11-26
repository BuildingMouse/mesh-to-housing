"""A column item and straight chains of it, shared by the tests."""
import numpy as np

from mesh_to_housing import Chain, Cuboid, Link

COLUMN = Cuboid("column", (0.2, 0.2, 0.8))
LINK = Link(COLUMN, COLUMN.shape.pose("long along, +thin up"), "middle", overlap=0.1, max_bend=30.0,
            max_overlap=0.35)


def straight_chain(count=3, scale=1.0, link=LINK, height=0.0):
    """Columns laid end to end along x, centered on the origin, overlapping a tenth of their length."""
    span = 0.8 * scale * 0.9
    joints = np.column_stack((np.arange(count + 1) * span - count * span / 2, np.zeros(count + 1),
                              np.full(count + 1, height)))
    return Chain(link, joints, np.tile((0.0, 0.0, 1.0), (count, 1)), np.full(count, scale))
