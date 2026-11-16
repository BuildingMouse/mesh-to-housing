"""World of Warcraft copy strings for the MouseHousingTools addon"""

from __future__ import annotations

import math
from typing import Iterable, Sequence

from . import packing

GAME = "wow"
VERSION = 1
COLORS = ("any", "same", "none")


def _number(value: float, digits: int) -> str:
    text = f"{value:.{digits}f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def rotation_degrees(matrix: Sequence[Sequence[float]]) -> tuple[float, float, float]:
    m = [[float(value) for value in row] for row in matrix]
    y = math.asin(max(-1.0, min(1.0, -m[2][0])))
    if abs(m[2][0]) < 1 - 1e-9:
        x = math.atan2(m[2][1], m[2][2])
        z = math.atan2(m[1][0], m[0][0])
    else:
        x, z = 0.0, math.atan2(-m[0][1], m[1][1])
    return math.degrees(x), math.degrees(y), math.degrees(z)


def build(
    item_id: int,
    centers: Iterable[Sequence[float]],
    rotations: Iterable[Sequence[Sequence[float]]],
    scales: Iterable[float],
    colors: str | Iterable[str] = "same",
) -> str:
    """The build text after the header: decor ID, then every instance of this decor."""
    centers, rotations, scales = list(centers), list(rotations), list(scales)
    colors = [colors] * len(centers) if isinstance(colors, str) else list(colors)
    if not (len(centers) == len(rotations) == len(scales) == len(colors)) or not centers:
        raise ValueError("centers, rotations, scales and colors need one entry per instance")
    lines = []
    for center, rotation, scale, color in zip(centers, rotations, scales, colors):
        if color not in COLORS:
            raise ValueError(f"unknown color {color!r}; use one of {', '.join(COLORS)}")
        shift = ",".join(_number(value, 3) for value in center)
        turn = ",".join(_number(value, 2) for value in rotation_degrees(rotation))
        lines.append(f"{shift} r{turn} s{_number(scale, 3)} {color}")
    return f"id={int(item_id)}:\n" + ";\n".join(lines)


def plain_text(*args, **kwargs) -> str:
    return packing.with_header(GAME, VERSION, build(*args, **kwargs))


def encode(*args, **kwargs) -> str:
    """The packed copy string players paste into the addon"""
    return packing.pack(plain_text(*args, **kwargs))
