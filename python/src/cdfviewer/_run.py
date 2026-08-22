"""
One process per call: `run`, `savefig` and `record`.

Each call starts the binary once, headlessly, waits for it to exit and
reads back what it logged: ``Warning:`` records become
`CDFViewerWarning`, an ``Error:`` record or a non-zero exit raise
`CDFViewerError`, and the ``Saved ... to`` line is where the returned
path comes from. In-memory input is written to a temporary file first
(`_data`) and the file is deleted once the process has exited.
"""

from __future__ import annotations

import codecs
import subprocess
import sys
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any

from . import _data
from ._command import command
from ._errors import CDFViewerError
from ._logs import parse_records, raise_for_records, saved_path

if TYPE_CHECKING:  # pragma: no cover
    import os
    from collections.abc import Mapping, Sequence
    from pathlib import Path

    from ._command import PathArg
    from ._logs import Record

_CHUNK = 65536


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

    Parameters
    ----------
    argv : Sequence[str]
        The command line to run, the binary first (see `command`).
    verbose : bool, optional
        Stream the app's output to ``sys.stderr`` while it runs, which
        is where a recording's progress bar shows (default: False).
    check : bool, optional
        Raise `CDFViewerError` when the binary exits non-zero
        (default: True).

    Returns
    -------
    RunResult
        The exit code, the combined output and its log records.

    Raises
    ------
    CDFViewerError
        When the binary does not exist, and, with ``check``, when it
        exits non-zero.
    """
    argv = [str(item) for item in argv]
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    chunks: list[str] = []
    try:
        # bytes, not text: text mode would turn the progress bar's
        # carriage returns into newlines.
        with subprocess.Popen(
            argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        ) as process:
            stream = process.stdout
            while chunk := stream.read1(_CHUNK):
                text = decoder.decode(chunk)
                chunks.append(text)
                if verbose:
                    sys.stderr.write(text)
                    sys.stderr.flush()
            returncode = process.wait()
    except FileNotFoundError as error:
        message = f"cannot run {argv[0]!r}: no such file"
        raise CDFViewerError(message, argv=argv) from error
    chunks.append(decoder.decode(b"", final=True))
    output = "".join(chunks)
    records = parse_records(output)
    if check and returncode != 0:
        raise CDFViewerError(
            f"cdfviewer exited with code {returncode}",
            returncode=returncode,
            argv=argv,
            output=output,
        )
    return RunResult(returncode, output, records)


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
    """
    Render one figure headlessly and return the file it was saved to.

    Parameters
    ----------
    path : str | PathLike | Sequence[str | PathLike] | Dataset | ndarray
        The dataset: one or more files, a zarr store, or in-memory data
        (an xarray ``Dataset``/``DataArray`` or a numpy array), which is
        written to a temporary file and deleted afterwards.
    var : str, optional
        The variable to plot; ``"u,v"`` names a vector pair.
    x, y, z : str, optional
        The dimensions on the axes.
    plot_type : str, optional
        The plot type, as for ``-p`` on the command line.
    ani_dim : str, optional
        The dimension an animation would run over.
    dims : Mapping[str, int], optional
        The index to fix each remaining dimension at.
    over : Sequence[str], optional
        Variables drawn as overlays on top of the main plot.
    over_plot : Sequence[str], optional
        The plot type of each overlay, matched to ``over`` by position.
    kwargs : Mapping[str, Any], optional
        Plot keywords, formatted for the app (see `format_value`).
    grid : str | PathLike, optional
        A grid file holding the coordinates.
    theme : str, optional
        The Makie theme to plot with.
    no_grid_search : bool, optional
        Do not look for a grid file next to the data (default: False).
    use_local : bool, optional
        Run in the dataset's directory (default: False).
    filename : str | PathLike, optional
        Where to write; the app picks its own name when this is left
        out. Relative names are taken from Python's working directory.
    px_per_unit : int, optional
        The resolution multiplier of the saved figure.
    overwrite : bool, optional
        Write over an existing file (the app's default is to do so);
        ``False`` keeps the ``name(1).ext`` numbering.
    complex_as : str, optional
        What to do with complex variables of in-memory input:
        ``"split"`` (default), ``"abs"``, ``"real"``, ``"imag"`` or
        ``"phase"``.
    verbose : bool, optional
        Stream the app's output to stderr (default: False).

    Returns
    -------
    Path
        The absolute path the app reported saving to.

    Raises
    ------
    CDFViewerError
        When the app fails, reports an error, or saves nothing.
    """
    return _one_shot(
        path,
        record=False,
        selection={
            "var": var, "x": x, "y": y, "z": z, "plot_type": plot_type,
            "ani_dim": ani_dim, "dims": dims, "over": over,
            "over_plot": over_plot, "kwargs": kwargs, "grid": grid,
            "theme": theme, "no_grid_search": no_grid_search,
            "use_local": use_local,
        },
        save={
            "filename": filename,
            "px_per_unit": px_per_unit,
            "overwrite": overwrite,
        },
        complex_as=complex_as,
        verbose=verbose,
    )


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
    """
    Record an animation headlessly and return the video file.

    Parameters
    ----------
    path : str | PathLike | Sequence[str | PathLike] | Dataset | ndarray
        The dataset, as for `savefig`.
    var : str, optional
        The variable to plot; ``"u,v"`` names a vector pair.
    x, y, z : str, optional
        The dimensions on the axes.
    plot_type : str, optional
        The plot type, as for ``-p`` on the command line.
    ani_dim : str, optional
        The dimension the animation runs over.
    dims : Mapping[str, int], optional
        The index to fix each remaining dimension at.
    over : Sequence[str], optional
        Variables drawn as overlays on top of the main plot.
    over_plot : Sequence[str], optional
        The plot type of each overlay, matched to ``over`` by position.
    kwargs : Mapping[str, Any], optional
        Plot keywords, formatted for the app (see `format_value`).
    grid : str | PathLike, optional
        A grid file holding the coordinates.
    theme : str, optional
        The Makie theme to plot with.
    no_grid_search : bool, optional
        Do not look for a grid file next to the data (default: False).
    use_local : bool, optional
        Run in the dataset's directory (default: False).
    filename : str | PathLike, optional
        Where to write; the app picks its own name when this is left
        out. Relative names are taken from Python's working directory.
    framerate : int, optional
        Frames per second of the recording.
    px_per_unit : int, optional
        The resolution multiplier of the recording.
    frames : Sequence[int], optional
        ``(start, stop)`` or ``(start, step, stop)``, 1-based and
        inclusive as in the app.
    overwrite : bool, optional
        Write over an existing file (the app's default is to do so);
        ``False`` keeps the ``name(1).ext`` numbering.
    complex_as : str, optional
        What to do with complex variables of in-memory input:
        ``"split"`` (default), ``"abs"``, ``"real"``, ``"imag"`` or
        ``"phase"``.
    verbose : bool, optional
        Stream the app's output to stderr, which is where the recording
        progress bar shows (default: False).

    Returns
    -------
    Path
        The absolute path the app reported saving to.

    Raises
    ------
    CDFViewerError
        When the app fails, reports an error, or saves nothing.
    """
    return _one_shot(
        path,
        record=True,
        selection={
            "var": var, "x": x, "y": y, "z": z, "plot_type": plot_type,
            "ani_dim": ani_dim, "dims": dims, "over": over,
            "over_plot": over_plot, "kwargs": kwargs, "grid": grid,
            "theme": theme, "no_grid_search": no_grid_search,
            "use_local": use_local,
        },
        save={
            "filename": filename,
            "framerate": framerate,
            "px_per_unit": px_per_unit,
            "frames": frames,
            "overwrite": overwrite,
        },
        complex_as=complex_as,
        verbose=verbose,
    )


def _one_shot(
    path: PathArg | Any,
    *,
    record: bool,
    selection: dict[str, Any],
    save: dict[str, Any],
    complex_as: str,
    verbose: bool,
) -> Path:
    """
    One headless run of the app that ends in a saved file.

    In-memory input is written to a temporary dataset first, whose
    variable name becomes the default ``var``; the temporary files are
    removed once the process has exited, which is why the cleanup can
    sit in a ``finally``.
    """
    temp = None
    if _data.is_in_memory(path):
        temp = _data.write_temp(
            path, complex_as=complex_as, var=selection["var"]
        )
        path = temp.path
        selection = {**selection, "var": temp.var or selection["var"]}
    try:
        argv = command(
            path,
            **selection,
            savefig=not record,
            record=record,
            no_summary=True,
            **save,
        )
        result = run(argv, verbose=verbose)
        raise_for_records(result.records, argv=argv, output=result.output)
        saved = saved_path(result.records)
        if saved is None:
            raise CDFViewerError(
                "cdfviewer did not report a saved file",
                returncode=result.returncode,
                argv=argv,
                output=result.output,
            )
        return saved
    finally:
        if temp is not None:
            temp.cleanup()
