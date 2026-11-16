from __future__ import annotations

import base64
import re
import zlib

PACKED_TAG = "mouse"

_READABLE = re.compile(r"^\s*[A-Za-z]+:\d+\s*/")


def with_header(game: str, version: int, build: str) -> str:
    """The game and its format version in front of the game's build text"""
    return f"{game}:{int(version)}/\n{build}"


def pack(text: str) -> str:
    """The plain-text copy string compressed with zlib, then written in standard Base64"""
    if not _READABLE.match(text):
        raise ValueError("expected a plain-text copy string such as 'wow:1/...'")
    packed = base64.b64encode(zlib.compress(text.strip().encode("utf-8"), 9)).decode("ascii")
    return f"{PACKED_TAG}:{packed}"


def unpack(text: str) -> str:
    """The plain text of a packed or plain-text copy string"""
    text = text.strip()
    tag, _, packed = text.partition(":")
    if tag.lower() == PACKED_TAG:
        text = zlib.decompress(base64.b64decode(packed)).decode("utf-8")
    if not _READABLE.match(text):
        raise ValueError("not a copy string")
    return text
