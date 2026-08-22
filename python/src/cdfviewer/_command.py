"""
The command line of one call, built from Python values.

`build_args` writes the CLI's options in the CLI's order; `command`
puts the resolved binary in front and hands back a `Command`.
"""

from __future__ import annotations

import os
import shlex
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any

from . import _binary
from ._format import format_dims, format_kwargs, format_save_options

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Mapping

PathArg = str | os.PathLike[str] | Sequence[str | os.PathLike[str]]


class Command(list[str]):

    """
    An argv list, the binary first, with a shell-quoted rendering.

    It is a plain ``list[str]`` and works anywhere argv is expected.
    """

    @property
    def shell(self) -> str:
        """The command line quoted for a POSIX shell."""
        return shlex.join(self)


def build_args(
    path: PathArg,
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
    menu: bool = False,
    no_summary: bool = False,
    savefig: bool = False,
    record: bool = False,
    filename: str | os.PathLike[str] | None = None,
    framerate: int | None = None,
    px_per_unit: int | None = None,
    frames: Sequence[int] | None = None,
    overwrite: bool | None = None,
) -> list[str]:
    """
    The arguments after the binary, in the CLI's order.

    Files first, then ``-v -x -y -z -p -a --dims=... --over X ...
    --over-plot Y ... --kwargs=... -g --theme``, the flags,
    ``--savefig``/``--record`` and ``-s ...``. Paths are made absolute;
    ``filename`` is ``~``-expanded and made absolute. In-memory datasets
    are not handled here.

    Raises
    ------
    ValueError
        For no path at all, for ``savefig`` together with ``record``, and
        for more ``over_plot`` entries than ``over`` entries.
    """
    if savefig and record:
        msg = "savefig and record exclude each other"
        raise ValueError(msg)
    over = list(over or ())
    over_plot = list(over_plot or ())
    if len(over_plot) > len(over):
        msg = "over_plot names more layers than over"
        raise ValueError(msg)
    args = _paths(path)
    options = (
        ("-v", var), ("-x", x), ("-y", y), ("-z", z), ("-p", plot_type),
        ("-a", ani_dim),
    )
    for flag, value in options:
        if value is not None:
            args += [flag, value]
    if dims:
        args.append(f"--dims={format_dims(dims)}")
    for layer in over:
        args += ["--over", layer]
    for layer_type in over_plot:
        args += ["--over-plot", layer_type]
    if kwargs:
        args.append(f"--kwargs={format_kwargs(kwargs)}")
    if grid is not None:
        args += ["-g", _absolute(grid)]
    if theme is not None:
        args += ["--theme", theme]
    flags = (
        ("--no-grid-search", no_grid_search), ("--use-local", use_local),
        ("--menu", menu), ("--no-summary", no_summary),
        ("--savefig", savefig), ("--record", record),
    )
    args += [flag for flag, on in flags if on]
    save = format_save_options(
        filename=None if filename is None else _absolute(filename),
        framerate=framerate,
        px_per_unit=px_per_unit,
        frames=frames,
        overwrite=overwrite,
    )
    if save:
        args += ["-s", save]
    return args


def _absolute(path: str | os.PathLike[str]) -> str:
    return os.path.abspath(os.path.expanduser(os.fspath(path)))  # noqa: PTH100, PTH111


def _paths(path: PathArg) -> list[str]:
    """The dataset paths as absolute strings; URLs are left alone."""
    items = [path] if isinstance(path, str | os.PathLike) else list(path)
    if not items:
        msg = "path must name at least one file"
        raise ValueError(msg)
    return [
        os.fspath(item) if "://" in os.fspath(item) else _absolute(item)
        for item in items
    ]


def command(
    path: PathArg,
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
    menu: bool = False,
    no_summary: bool = False,
    savefig: bool = False,
    record: bool = False,
    filename: str | os.PathLike[str] | None = None,
    framerate: int | None = None,
    px_per_unit: int | None = None,
    frames: Sequence[int] | None = None,
    overwrite: bool | None = None,
) -> Command:
    """
    The full command line, the resolved binary first.

    The same parameters as `savefig`, `record` and `Session`, but nothing
    is run: use it for job scripts, papers, dry runs, or your own runner.
    ``.shell`` gives the line quoted for a shell.
    """
    args = build_args(
        path, var=var, x=x, y=y, z=z, plot_type=plot_type, ani_dim=ani_dim,
        dims=dims, over=over, over_plot=over_plot, kwargs=kwargs, grid=grid,
        theme=theme, no_grid_search=no_grid_search, use_local=use_local,
        menu=menu, no_summary=no_summary, savefig=savefig, record=record,
        filename=filename, framerate=framerate, px_per_unit=px_per_unit,
        frames=frames, overwrite=overwrite,
    )
    return Command([str(_binary.resolve()), *args])
