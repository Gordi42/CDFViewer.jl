"""
Python values written in the app's keyword syntax.

The app parses its ``--kwargs`` line itself: quoted strings, ``:symbols``,
numbers, ``true``/``false``/``nothing``, tuples, arrays, and anything
else as a Julia expression. This module only prints Python values in
that syntax; it never evaluates anything.
"""

from __future__ import annotations

import datetime as dt
import math
import os
from collections.abc import Mapping, Sequence
from typing import Any

_RANGE_HINT = (
    "Python ranges are half-open and Julia ranges inclusive, so a range "
    "is not translated; write it as raw('1:10'), or for a recording use "
    "frames=(start, stop)"
)


class Sym(str):

    """A Julia symbol: ``sym("balance")`` is written as ``:balance``."""

    __slots__ = ()


class Raw(str):

    """Verbatim Julia text, written exactly as given."""

    __slots__ = ()


def sym(name: str) -> Sym:
    """
    A Julia symbol.

    Makie accepts colors and colormaps as plain strings, so this is only
    needed for keywords that want a symbol, e.g. ``animlabelpos=sym("lt")``.
    """
    return Sym(name)


def raw(text: str) -> Raw:
    """
    Verbatim Julia text, the escape hatch for any expression.

    ``raw("Makie.Symlog10(1e-2)")`` reaches the app unquoted and is
    evaluated there, in its sandbox.
    """
    return Raw(text)


def _unwrap_numpy(value: object) -> object:
    """A numpy scalar as the Python scalar, a numpy array as nested lists."""
    module = type(value).__module__
    if module == "numpy" or module.startswith("numpy."):
        tolist = getattr(value, "tolist", None)
        if tolist is not None:
            return tolist()
    return value


def format_value(value: object) -> str:
    r"""
    One value in the app's keyword syntax.

    Strings are quoted (``"`` and ``\\`` escaped), ``bool`` and ``None``
    become ``true``/``false``/``nothing``, tuples and lists keep their
    brackets, ``datetime``/``date`` become ``DateTime(...)``/``Date(...)``,
    `Sym` and `Raw` are written as a symbol and verbatim. Nested values
    are formatted recursively; numpy scalars and arrays are unwrapped
    first.

    Raises
    ------
    TypeError
        For ``range`` and ``slice`` (inclusive/half-open mismatch), for a
        timezone-aware datetime, and for any other type.
    """
    value = _unwrap_numpy(value)
    if isinstance(value, Raw):
        return str.__str__(value)
    if isinstance(value, Sym):
        return f":{value}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nothing"
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "NaN"
        if math.isinf(value):
            return "Inf" if value > 0 else "-Inf"
        return repr(value)
    if isinstance(value, dt.datetime):
        if value.tzinfo is not None:
            msg = (
                "a timezone-aware datetime cannot be written as a Julia "
                "DateTime; convert it to a naive one first"
            )
            raise TypeError(msg)
        return f'DateTime("{value.isoformat(timespec="milliseconds")}")'
    if isinstance(value, dt.date):
        return f'Date("{value.isoformat()}")'
    if isinstance(value, range | slice):
        raise TypeError(_RANGE_HINT)
    if isinstance(value, tuple):
        if len(value) == 1:
            return f"({format_value(value[0])},)"
        return "(" + ", ".join(format_value(v) for v in value) + ")"
    if isinstance(value, list):
        return "[" + ", ".join(format_value(v) for v in value) + "]"
    if isinstance(value, os.PathLike):
        return format_value(os.fspath(value))
    msg = (
        f"cannot write a {type(value).__name__} as a keyword value; "
        "use a plain Python value, sym() or raw()"
    )
    raise TypeError(msg)


def format_kwargs(kwargs: Mapping[str, Any]) -> str:
    """The ``--kwargs`` line: ``key=value`` pairs joined by commas."""
    return ", ".join(
        f"{key}={format_value(value)}" for key, value in kwargs.items()
    )


def _as_int(name: str, value: object) -> int:
    value = _unwrap_numpy(value)
    if isinstance(value, bool) or not isinstance(value, int):
        msg = f"{name} must be an int, got {type(value).__name__}"
        raise TypeError(msg)
    return value


def format_dims(dims: Mapping[str, Any]) -> str:
    """The ``--dims`` value: ``name=index`` pairs joined by commas."""
    return ",".join(
        f"{name}={_as_int(f'dims[{name!r}]', index)}"
        for name, index in dims.items()
    )


def _frames_range(frames: object) -> str:
    if not isinstance(frames, Sequence) or isinstance(frames, str):
        msg = "frames must be (start, stop) or (start, step, stop)"
        raise TypeError(msg)
    values = [_as_int("frames", v) for v in frames]
    if len(values) not in (2, 3):
        msg = "frames must be (start, stop) or (start, step, stop)"
        raise TypeError(msg)
    return ":".join(str(v) for v in values)


def format_save_options(
    *,
    filename: str | os.PathLike[str] | None = None,
    framerate: int | None = None,
    px_per_unit: int | None = None,
    frames: Sequence[int] | None = None,
    overwrite: bool | None = None,
) -> str:
    """
    The ``-s`` line, holding only the options that were set.

    ``frames`` is ``(start, stop)`` or ``(start, step, stop)`` in the
    app's own convention, 1-based and inclusive, and becomes
    ``range=start:step:stop``.
    """
    parts: list[str] = []
    if filename is not None:
        parts.append(f"filename={format_value(os.fspath(filename))}")
    if framerate is not None:
        parts.append(f"framerate={_as_int('framerate', framerate)}")
    if px_per_unit is not None:
        parts.append(f"px_per_unit={_as_int('px_per_unit', px_per_unit)}")
    if frames is not None:
        parts.append(f"range={_frames_range(frames)}")
    if overwrite is not None:
        parts.append(f"overwrite={format_value(bool(overwrite))}")
    return ", ".join(parts)
