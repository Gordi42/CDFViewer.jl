"""
A live viewer, driven through the app's REPL over a pipe.

A `Session` declares a state: constructing one either starts the app or,
with ``reuse``, hands back the viewer already open on the same dataset
and sends it the differences. The process is talked to over a pipe --
one line in, everything up to the next ``CDFViewer> `` prompt out --
while a daemon thread drains the pipe at all times, because an undrained
pipe would block the app and freeze its window.

See ``design/python/api.md`` (Q1 and its addendum) for the contract.
"""

from __future__ import annotations

import atexit
import contextlib
import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any, NoReturn, Self

from . import _binary, _config, _data
from ._command import _absolute, _paths, build_args
from ._errors import CDFViewerError
from ._format import format_kwargs, format_save_options
from ._logs import (
    parse_records,
    raise_for_records,
    saved_path,
    strip_progress,
)

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Mapping, Sequence

    from ._command import PathArg

PROMPT = "CDFViewer> "
_PROMPT_BYTES = PROMPT.encode()
_CHUNK = 65536
_CLOSE_TIMEOUT = 10.0
_FIRST_OVER = 2  # `over` is layer 2; `over2` is layer 3

#: What a declaration may name, in the order the app is set up in.
DECLARATION_KEYS = (
    "var",
    "plot_type",
    "x",
    "y",
    "z",
    "dims",
    "ani_dim",
    "over",
    "over_plot",
    "kwargs",
    "theme",
)
_MAPPING_KEYS = ("dims", "kwargs")
_LIST_KEYS = ("over", "over_plot")

_REGISTRY: dict[tuple[Any, ...], Session] = {}


def _layer_prefix(layer: int) -> str:
    """The REPL prefix addressing a layer: ``over``, ``over2``, ..."""
    if layer < _FIRST_OVER:
        msg = f"layer must be 2 or more, got {layer} (1 is the base layer)"
        raise ValueError(msg)
    return "over" if layer == _FIRST_OVER else f"over{layer - 1}"


def _registry_key(
    path: PathArg | Any,
    *,
    grid: str | os.PathLike[str] | None,
    use_local: bool,
) -> tuple[Any, ...]:
    """
    What identifies the dataset a session is open on.

    The resolved paths (or the identity of an in-memory object) plus the
    options that cannot be changed once the app runs.
    """
    grid_key = None if grid is None else _absolute(grid)
    if _data.is_in_memory(path):
        return ("object", id(path), grid_key, use_local)
    return ("paths", tuple(_paths(path)), grid_key, use_local)


def _normalise(declaration: Mapping[str, Any]) -> dict[str, Any]:
    """
    A declaration with its unset entries dropped and its containers copied.

    ``None`` means "not declared": what a declaration does not mention is
    left as it is.
    """
    unknown = sorted(set(declaration) - set(DECLARATION_KEYS))
    if unknown:
        msg = f"not part of a declaration: {', '.join(unknown)}"
        raise TypeError(msg)
    declared: dict[str, Any] = {}
    for key, value in declaration.items():
        if value is None:
            continue
        if key in _MAPPING_KEYS:
            declared[key] = dict(value)
        elif key in _LIST_KEYS:
            declared[key] = list(value)
        else:
            declared[key] = value
    return declared


class Session:

    """
    A running viewer on one dataset, controlled from Python.

    Constructing one either starts the app or, with ``reuse`` (the
    default), returns the session already open on the same dataset and
    applies the declaration to it. The window stays open until `close`.

    Parameters
    ----------
    path : str | PathLike | Sequence | Dataset | DataArray | ndarray
        The dataset: one or more files, a zarr store, or in-memory data,
        which is written to a temporary file first.
    var, x, y, z, plot_type, ani_dim, dims, over, over_plot, kwargs, theme
        The selection, as on the command line; together they are the
        session's *declaration* (see `apply`).
    grid : str | PathLike, optional
        A separate grid file (``-g``); part of the registry key.
    no_grid_search, use_local, menu, no_summary : bool, optional
        The command line's flags (default: False). ``use_local`` is part
        of the registry key.
    reuse : bool, optional
        Hand back the session already open on this dataset instead of
        starting a second viewer (default: True).
    visible : bool, optional
        Show the figure window; ``False`` sends ``hide`` right after
        startup (default: True).
    verbose : bool, optional
        Echo everything the app prints to `sys.stderr` (default: False).
    complex_as : str, optional
        How complex in-memory data is written (default: "split").
    timeout : float, optional
        Seconds to wait for the app's prompt, startup included
        (default: 120.0).

    Raises
    ------
    CDFViewerError
        When the app exits before its first prompt, when it does not
        answer within ``timeout``, and when it logs an ``Error`` record.
    """

    def __new__(cls, path: PathArg | Any, **kwargs: Any) -> Self:
        """The session registered on this dataset, or a fresh object."""
        if not kwargs.get("reuse", True):
            return super().__new__(cls)
        key = _registry_key(
            path,
            grid=kwargs.get("grid"),
            use_local=kwargs.get("use_local", False),
        )
        existing = _REGISTRY.get(key)
        if existing is None:
            return super().__new__(cls)
        if existing.alive:
            return existing
        existing.close()  # a dead session is dropped and replaced
        return super().__new__(cls)

    def __init__(
        self,
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
        menu: bool = False,
        no_summary: bool = False,
        # read by __new__, which decides whether this is a new process
        reuse: bool = True,  # noqa: ARG002
        visible: bool = True,
        verbose: bool = False,
        complex_as: str = "split",
        timeout: float = 120.0,
    ) -> None:
        declaration = {
            "var": var,
            "plot_type": plot_type,
            "x": x,
            "y": y,
            "z": z,
            "dims": dims,
            "ani_dim": ani_dim,
            "over": over,
            "over_plot": over_plot,
            "kwargs": kwargs,
            "theme": theme,
        }
        if getattr(self, "_started", False):
            self.apply(**declaration)  # a reused session, already running
            return
        self._verbose = verbose
        self._timeout = timeout
        self._temp: _data.TempDataset | None = None
        self._object: Any = None
        self._key = _registry_key(path, grid=grid, use_local=use_local)
        binary = _binary.resolve()
        if _data.is_in_memory(path):
            self._object = path  # keeps id(path) valid while we live
            self._temp = _data.write_temp(
                path, complex_as=complex_as, var=var
            )
            path = self._temp.path
            if self._temp.var is not None:
                var = self._temp.var
        # a save without a filename is reported relative to this
        self._cwd = Path.cwd()
        self._argv = [
            str(binary),
            *build_args(
                path, var=var, x=x, y=y, z=z, plot_type=plot_type,
                ani_dim=ani_dim, dims=dims, over=over, over_plot=over_plot,
                kwargs=kwargs, grid=grid, theme=theme,
                no_grid_search=no_grid_search, use_local=use_local,
                menu=menu, no_summary=no_summary,
            ),
        ]
        self._declared = _normalise(declaration)
        self._buffer = bytearray()
        self._eof = False
        self._condition = threading.Condition()
        self._proc = subprocess.Popen(
            self._argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
        self._reader = threading.Thread(
            target=self._drain,
            name=f"cdfviewer-reader-{self._proc.pid}",
            daemon=True,
        )
        self._reader.start()
        try:
            text = self._wait_for_prompt(timeout)
            raise_for_records(
                parse_records(text), argv=self._argv, output=text
            )
            if not visible:
                self.hide()
        except Exception:
            self.close()
            raise
        self._started = True
        _REGISTRY[self._key] = self

    # ------------------------------------------------------- the pipe ----

    def _drain(self) -> None:
        """Read the app's output for as long as it runs (the reader thread)."""
        fd = self._proc.stdout.fileno()
        while True:
            try:
                chunk = os.read(fd, _CHUNK)
            except (OSError, ValueError):  # pragma: no cover
                chunk = b""
            if chunk and self._verbose:
                sys.stderr.write(chunk.decode("utf-8", errors="replace"))
                sys.stderr.flush()
            with self._condition:
                if not chunk:
                    self._eof = True
                    self._condition.notify_all()
                    return
                self._buffer += chunk
                self._condition.notify_all()

    @staticmethod
    def _decode(data: bytes | bytearray) -> str:
        return strip_progress(bytes(data).decode("utf-8", errors="replace"))

    def _exited(self) -> NoReturn:
        """Raise: the app is gone and no prompt is coming. Holds the lock."""
        text = self._decode(self._buffer)
        self._buffer.clear()
        returncode = self._proc.wait(timeout=_CLOSE_TIMEOUT)
        msg = f"cdfviewer exited with code {returncode}"
        raise CDFViewerError(
            msg, returncode=returncode, argv=self._argv, output=text
        )

    def _wait_for_prompt(self, timeout: float) -> str:
        """Everything the app printed up to the next prompt, prompt removed."""
        deadline = time.monotonic() + timeout
        with self._condition:
            while not self._buffer.endswith(_PROMPT_BYTES):
                if self._eof:
                    self._exited()
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    msg = (
                        f"cdfviewer did not answer within {timeout:g} s "
                        "(timeout)"
                    )
                    raise CDFViewerError(
                        msg,
                        argv=self._argv,
                        output=self._decode(self._buffer),
                    )
                self._condition.wait(remaining)
            text = self._decode(self._buffer[: -len(_PROMPT_BYTES)])
            self._buffer.clear()
        return text

    @property
    def pid(self) -> int:
        """The process id of the app."""
        return self._proc.pid

    @property
    def alive(self) -> bool:
        """Whether the app is still running."""
        return self._proc.poll() is None

    def send(self, line: str, *, timeout: float | None = None) -> str:
        """
        Send one REPL line and return what it printed before the prompt.

        Output that arrived unsolicited since the last call is part of
        the answer and is checked with it: ``Warning`` records become
        `CDFViewerWarning`, an ``Error`` record raises, and the session
        stays alive either way.

        Parameters
        ----------
        line : str
            The REPL command, without its newline.
        timeout : float, optional
            Seconds to wait for the prompt (default: the session's).

        Returns
        -------
        str
            The app's output, progress redraws removed.
        """
        if not self.alive:
            msg = (
                "the viewer is no longer running "
                f"(exit code {self._proc.returncode})"
            )
            raise CDFViewerError(
                msg, returncode=self._proc.returncode, argv=self._argv
            )
        try:
            self._proc.stdin.write(line.encode() + b"\n")
            self._proc.stdin.flush()
        except (BrokenPipeError, ValueError) as exc:
            msg = f"could not send {line!r}: the viewer closed its input"
            raise CDFViewerError(msg, argv=self._argv) from exc
        text = self._wait_for_prompt(
            self._timeout if timeout is None else timeout
        )
        raise_for_records(
            parse_records(text), argv=self._argv, output=text
        )
        return text

    # --------------------------------------------------- the vocabulary ----

    def var(self, name: str) -> None:
        """Select the variable (``v name``)."""
        self.send(f"v {name}")

    def plot(self, plot_type: str) -> None:
        """Select the plot type (``p type``)."""
        self.send(f"p {plot_type}")

    def axes(
        self,
        *,
        x: str | None = None,
        y: str | None = None,
        z: str | None = None,
    ) -> None:
        """Select the axis variables (``x``, ``y``, ``z``)."""
        for axis, name in (("x", x), ("y", y), ("z", z)):
            if name is not None:
                self.send(f"{axis} {name}")

    def isel(self, **dims: int) -> None:
        """Select dimension indices (``isel dim index``)."""
        for name, index in dims.items():
            self.send(f"isel {name} {index}")

    def sel(self, **dims: Any) -> None:
        """Select dimension values (``sel dim value``)."""
        for name, value in dims.items():
            self.send(f"sel {name} {value}")

    def over(
        self,
        var: str | None,
        plot_type: str | None = None,
        *,
        layer: int = 2,
    ) -> None:
        """
        Draw (or with ``None`` remove) an overlaid layer (``over ...``).

        Parameters
        ----------
        var : str | None
            The variable of the layer; ``None`` removes it (``over off``).
        plot_type : str, optional
            The layer's plot type (``over.p type``); left alone when it
            is not given (default: None).
        layer : int, optional
            Which layer: 2 is ``over``, 3 is ``over2``, ... (default: 2).
        """
        prefix = _layer_prefix(layer)
        self.send(f"{prefix} {'off' if var is None else var}")
        if plot_type is not None:
            self.send(f"{prefix}.p {plot_type}")

    def set(self, **kwargs: Any) -> None:
        """Apply a keyword line (``key=value, ...``)."""
        self.send(format_kwargs(kwargs))

    def delete(self, *names: str) -> None:
        """Delete keywords (``del name``)."""
        for name in names:
            self.send(f"del {name}")

    def get(self, name: str) -> str:
        """
        The value of a keyword as the app reports it (``get name``).

        Returns
        -------
        str
            The text after ``name => `` in the app's answer, e.g.
            ``":balance"``.
        """
        text = self.send(f"get {name}")
        prefix = f"{name} => "
        for record in parse_records(text):
            if record.level == "Info" and record.message.startswith(prefix):
                return record.message[len(prefix):]
        msg = f"cdfviewer did not report a value for {name!r}"
        raise CDFViewerError(msg, argv=self._argv, output=text)

    def _save(self, command: str, options: str) -> Path:
        text = self.send(f"{command} {options}".strip())
        path = saved_path(parse_records(text))
        if path is None:
            msg = f"cdfviewer did not report where {command} wrote"
            raise CDFViewerError(msg, argv=self._argv, output=text)
        return path if path.is_absolute() else self._cwd / path

    def savefig(
        self,
        filename: str | os.PathLike[str] | None = None,
        *,
        px_per_unit: int | None = None,
        overwrite: bool | None = None,
    ) -> Path:
        """
        Save the current figure and return the file.

        Parameters
        ----------
        filename : str | PathLike, optional
            Where to write; ``~`` is expanded and the path is made
            absolute. Without one the app picks its standard name
            (default: None).
        px_per_unit : int, optional
            Resolution multiplier (default: the app's).
        overwrite : bool, optional
            Write over an existing file; ``False`` keeps the app's
            ``name(1).ext`` numbering (default: the app's).

        Returns
        -------
        Path
            The file the app reported writing.
        """
        return self._save(
            "savefig",
            format_save_options(
                filename=None if filename is None else _absolute(filename),
                px_per_unit=px_per_unit,
                overwrite=overwrite,
            ),
        )

    def record(
        self,
        filename: str | os.PathLike[str] | None = None,
        *,
        framerate: int | None = None,
        px_per_unit: int | None = None,
        frames: Sequence[int] | None = None,
        overwrite: bool | None = None,
    ) -> Path:
        """
        Record the animation and return the video file.

        Parameters
        ----------
        filename : str | PathLike, optional
            Where to write, as for `savefig` (default: None).
        framerate : int, optional
            Frames per second (default: the app's).
        px_per_unit : int, optional
            Resolution multiplier (default: the app's).
        frames : Sequence[int], optional
            ``(start, stop)`` or ``(start, step, stop)``, 1-based and
            inclusive (default: every frame).
        overwrite : bool, optional
            As for `savefig` (default: the app's).

        Returns
        -------
        Path
            The file the app reported writing.
        """
        return self._save(
            "record",
            format_save_options(
                filename=None if filename is None else _absolute(filename),
                framerate=framerate,
                px_per_unit=px_per_unit,
                frames=frames,
                overwrite=overwrite,
            ),
        )

    def theme(self, name: str) -> None:
        """Switch the Makie theme (``theme name``)."""
        self.send(f"theme {name}")

    def reset(self) -> None:
        """Reset the plot settings (``reset``)."""
        self.send("reset")

    def export(self) -> str:
        """
        The CLI argument line reproducing the current state.

        Returns
        -------
        str
            The last line of the app's ``export`` block, which is the
            command line's arguments -- the counterpart of `command`.
        """
        text = self.send("export")
        infos = [r for r in parse_records(text) if r.level == "Info"]
        if not infos:
            msg = "cdfviewer did not answer the export command"
            raise CDFViewerError(msg, argv=self._argv, output=text)
        return infos[-1].message.splitlines()[-1]

    def show(self) -> None:
        """Show the figure window."""
        self.send("show")

    def hide(self) -> None:
        """Hide the figure window."""
        self.send("hide")

    def png(self) -> bytes:
        """
        The current figure as PNG bytes.

        Saves to a temporary file under the configured temp directory,
        reads it and deletes it, so a notebook can show the figure
        inline (`_repr_png_` calls this).
        """
        with tempfile.TemporaryDirectory(
            prefix="cdfviewer-", dir=_config.tmpdir()
        ) as directory:
            saved = self.savefig(
                Path(directory) / "figure.png", overwrite=True
            )
            return saved.read_bytes()

    def _repr_png_(self) -> bytes:
        return self.png()

    # ---------------------------------------------------- declarations ----

    def _differs(self, declared: Mapping[str, Any], key: str) -> bool:
        return key in declared and declared[key] != self._declared.get(key)

    def _apply_selection(self, declared: Mapping[str, Any]) -> None:
        """Variable, plot type, axes, dimensions, animation dimension."""
        if self._differs(declared, "var"):
            self.var(declared["var"])
        if self._differs(declared, "plot_type"):
            self.plot(declared["plot_type"])
        axes = {
            axis: declared[axis]
            for axis in ("x", "y", "z")
            if self._differs(declared, axis)
        }
        if axes:
            self.axes(**axes)
        if "dims" in declared:
            before = self._declared.get("dims") or {}
            moved = {
                name: index
                for name, index in declared["dims"].items()
                if before.get(name) != index
            }
            if moved:
                self.isel(**moved)
        if self._differs(declared, "ani_dim"):
            self.send(f"pdim {declared['ani_dim']}")

    def _apply_layers(self, declared: Mapping[str, Any]) -> None:
        """The overlaid layers, position by position."""
        if not ({"over", "over_plot"} & set(declared)):
            return
        new_vars = declared.get("over", [])
        old_vars = self._declared.get("over") or []
        new_types = declared.get("over_plot", [])
        old_types = self._declared.get("over_plot") or []
        count = max(
            len(new_vars), len(old_vars), len(new_types), len(old_types)
        )
        dropped: list[int] = []
        for index in range(count):
            layer = index + _FIRST_OVER
            new_var = _at(new_vars, index)
            new_type = _at(new_types, index)
            var_changed = "over" in declared and new_var != _at(
                old_vars, index
            )
            type_changed = "over_plot" in declared and new_type != _at(
                old_types, index
            )
            if var_changed and new_var is None:
                dropped.append(layer)  # removed last: it renames the rest
            elif var_changed:
                self.over(
                    new_var, new_type if type_changed else None, layer=layer
                )
            elif type_changed and new_type is not None:
                self.send(f"{_layer_prefix(layer)}.p {new_type}")
        for layer in reversed(dropped):
            self.over(None, layer=layer)

    def _apply_kwargs(self, declared: Mapping[str, Any]) -> None:
        """Set what changed, delete what the declaration dropped."""
        if "kwargs" not in declared:
            return
        before = self._declared.get("kwargs") or {}
        now = declared["kwargs"]
        changed = {
            key: value
            for key, value in now.items()
            if key not in before or before[key] != value
        }
        if changed:
            self.send(format_kwargs(changed))
        gone = [key for key in before if key not in now]
        if gone:
            self.delete(*gone)

    def apply(self, **declaration: Any) -> None:
        """
        Make the viewer match a declaration, sending only the changes.

        The declaration is the selection (``var``, ``x``, ``y``, ``z``,
        ``plot_type``, ``ani_dim``, ``dims``, ``over``, ``over_plot``,
        ``kwargs``, ``theme``). It is compared with the session's last
        one and the differences go out in the app's setup order.
        Keywords that were declared before and are gone now are deleted;
        anything the declaration never mentions -- set by mouse, menu or
        `set` -- is left alone, ``None`` meaning "not mentioned".

        Raises
        ------
        TypeError
            For a keyword that is not part of a declaration.
        """
        declared = _normalise(declaration)
        self._apply_selection(declared)
        self._apply_layers(declared)
        self._apply_kwargs(declared)
        if self._differs(declared, "theme"):
            self.theme(declared["theme"])
        self._declared.update(declared)

    # ------------------------------------------------------- lifetime ----

    def close(self) -> None:
        """
        End the session: close the pipe, wait for the app to exit.

        Idempotent, and safe on a session whose app has already gone.
        Any temporary file written for in-memory input is deleted once
        the process is out of the way.
        """
        if _REGISTRY.get(self._key) is self:
            del _REGISTRY[self._key]
        proc = self._proc
        if not proc.stdin.closed:
            with contextlib.suppress(BrokenPipeError):
                proc.stdin.close()
        if proc.poll() is None:
            try:
                proc.wait(timeout=_CLOSE_TIMEOUT)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=_CLOSE_TIMEOUT)
        self._reader.join(timeout=_CLOSE_TIMEOUT)
        if not proc.stdout.closed:
            proc.stdout.close()
        if self._temp is not None:
            self._temp.cleanup()
            self._temp = None

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


def _at(values: Sequence[str], index: int) -> str | None:
    """The entry at ``index``, or ``None`` past the end."""
    return values[index] if index < len(values) else None


def sessions() -> list[Session]:
    """Every live session of this process."""
    return [session for session in _REGISTRY.values() if session.alive]


def close_all() -> None:
    """Close every live session."""
    for session in list(_REGISTRY.values()):
        session.close()


atexit.register(close_all)
