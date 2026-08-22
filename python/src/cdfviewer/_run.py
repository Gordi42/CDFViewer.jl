"""
One process per call: `run`, `savefig` and `record`.

Work package C (stubs).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    import os
    from collections.abc import Mapping, Sequence
    from pathlib import Path

    from ._command import PathArg
    from ._logs import Record


@dataclass
class RunResult:

    """What one run of the binary produced."""

    returncode: int
    output: str
    records: list[Record] = field(default_factory=list)


def run(
    argv: Sequence[str], *, verbose: bool = False, check: bool = True
) -> RunResult:
    """
    Run the binary with ``argv`` and collect its output.

    stdout and stderr are captured together; with ``verbose`` they are
    also streamed to ``sys.stderr`` as they arrive. With ``check`` a
    non-zero exit raises `CDFViewerError`.
    """
    raise NotImplementedError


def savefig(
    path: PathArg | Any,
    *,
    var: str | None = None,
    x: str | None = None,
    y: str | None = None,
    z: str | None = None,
    plot_type: str | None = None,
    ani_dim: str | None = None,
    dims: Mapping[str, int] | None = None,
    over: Sequence[str] | None = None,
    over_plot: Sequence[str] | None = None,
    kwargs: Mapping[str, Any] | None = None,
    grid: str | os.PathLike[str] | None = None,
    theme: str | None = None,
    no_grid_search: bool = False,
    use_local: bool = False,
    filename: str | os.PathLike[str] | None = None,
    px_per_unit: int | None = None,
    overwrite: bool | None = None,
    complex_as: str = "split",
    verbose: bool = False,
) -> Path:
    """Render one figure headlessly and return the file it was saved to."""
    raise NotImplementedError


def record(
    path: PathArg | Any,
    *,
    var: str | None = None,
    x: str | None = None,
    y: str | None = None,
    z: str | None = None,
    plot_type: str | None = None,
    ani_dim: str | None = None,
    dims: Mapping[str, int] | None = None,
    over: Sequence[str] | None = None,
    over_plot: Sequence[str] | None = None,
    kwargs: Mapping[str, Any] | None = None,
    grid: str | os.PathLike[str] | None = None,
    theme: str | None = None,
    no_grid_search: bool = False,
    use_local: bool = False,
    filename: str | os.PathLike[str] | None = None,
    framerate: int | None = None,
    px_per_unit: int | None = None,
    frames: Sequence[int] | None = None,
    overwrite: bool | None = None,
    complex_as: str = "split",
    verbose: bool = False,
) -> Path:
    """Record an animation headlessly and return the video file."""
    raise NotImplementedError
