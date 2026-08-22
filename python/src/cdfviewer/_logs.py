"""
The app's log output, read back into records.

The app logs through Julia's logger, to stderr, in four shapes::

    [ Info: message
    ┌ Info: first line
    │ more
    └ last line
    ┌ Warning: message
    └ @ CDFViewer.Module /path/file.jl:123
    ┌ Error: message
    └ @ CDFViewer.Module /path/file.jl:123

A recording first prints a progress bar (carriage returns and ANSI erase
sequences), and a save ends with ``Saved figure to <path>`` or ``Saved
animation to <path>``, which is how the package learns where the file
went.
"""

from __future__ import annotations

import re
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from ._errors import CDFViewerError, CDFViewerWarning

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Iterable, Sequence

LEVELS = ("Info", "Warning", "Error", "Debug")
_LEVEL = "|".join(LEVELS)
_SINGLE = re.compile(rf"^\[ ({_LEVEL}): ?(.*)$")
_BLOCK_START = re.compile(rf"^┌ ({_LEVEL}): ?(.*)$")
_BLOCK_MIDDLE = re.compile(r"^│ ?(.*)$")
_BLOCK_END = re.compile(r"^└ ?(.*)$")
_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
_SAVED = re.compile(r"^Saved (?:figure|animation) to (.+)$")


@dataclass(frozen=True)
class Record:

    """One log record: its level (``Info``, ``Warning``, ...) and text."""

    level: str
    message: str


def strip_progress(text: str) -> str:
    """
    The text without progress-bar redraws and ANSI escape sequences.

    On every line only what follows the last carriage return is kept,
    which is what a terminal would show.
    """
    text = _ANSI.sub("", text)
    return "\n".join(line.rsplit("\r", 1)[-1] for line in text.split("\n"))


def parse_records(text: str) -> list[Record]:
    """
    Every log record in ``text``, in order; other lines are skipped.

    A multi-line block's lines are joined with newlines; its trailing
    ``@ Module file:line`` location is dropped.
    """
    records: list[Record] = []
    level: str | None = None
    lines: list[str] = []

    def flush() -> None:
        nonlocal level, lines
        if level is not None:
            records.append(Record(level, "\n".join(lines)))
        level, lines = None, []

    for line in strip_progress(text).split("\n"):
        if level is not None:
            if match := _BLOCK_END.match(line):
                tail = match.group(1)
                if tail and not tail.startswith("@ "):
                    lines.append(tail)
                flush()
                continue
            if match := _BLOCK_MIDDLE.match(line):
                lines.append(match.group(1))
                continue
            flush()  # a block that never closed
        if match := _SINGLE.match(line):
            records.append(Record(match.group(1), match.group(2)))
        elif match := _BLOCK_START.match(line):
            level, lines = match.group(1), [match.group(2)]
    flush()
    return records


def saved_path(records: Iterable[Record]) -> Path | None:
    """The path of the last ``Saved figure/animation to`` record, if any."""
    found: Path | None = None
    for record in records:
        if record.level == "Info" and (match := _SAVED.match(record.message)):
            found = Path(match.group(1))
    return found


def raise_for_records(
    records: Iterable[Record],
    *,
    argv: Sequence[str] | None = None,
    output: str = "",
) -> None:
    """
    Turn the app's records into Python signals.

    Every ``Warning`` becomes a `CDFViewerWarning`; if there is any
    ``Error``, a `CDFViewerError` naming it is raised after the warnings
    were issued.
    """
    records = list(records)
    for record in records:
        if record.level == "Warning":
            warnings.warn(record.message, CDFViewerWarning, stacklevel=3)
    errors = [r.message for r in records if r.level == "Error"]
    if not errors:
        return
    if len(errors) == 1:
        message = f"cdfviewer reported an error: {errors[0]}"
    else:
        message = f"cdfviewer reported {len(errors)} errors: " + " | ".join(
            errors
        )
    raise CDFViewerError(message, argv=argv, output=output)
