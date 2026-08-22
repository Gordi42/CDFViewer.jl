"""
A live viewer, driven through the app's REPL over a pipe.

Work package D (stubs). See ``design/python/api.md`` (Q1 and its
addendum) for the contract: a `Session` declares a state, the registry
reuses a running viewer on the same dataset, and the window lives until
`Session.close`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Self

if TYPE_CHECKING:  # pragma: no cover
    import os
    from collections.abc import Mapping, Sequence
    from pathlib import Path

    from ._command import PathArg

PROMPT = "CDFViewer> "


class Session:

    """
    A running viewer on one dataset, controlled from Python.

    Constructing one either starts the app or, with ``reuse`` (the
    default), returns the session already open on the same dataset and
    applies the declaration to it. The window stays open until `close`.
    """

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
        reuse: bool = True,
        visible: bool = True,
        verbose: bool = False,
        complex_as: str = "split",
        timeout: float = 120.0,
    ) -> None:
        raise NotImplementedError

    @property
    def pid(self) -> int:
        """The process id of the app."""
        raise NotImplementedError

    @property
    def alive(self) -> bool:
        """Whether the app is still running."""
        raise NotImplementedError

    def send(self, line: str, *, timeout: float | None = None) -> str:
        """Send one REPL line and return what it printed before the prompt."""
        raise NotImplementedError

    def apply(self, **declaration: Any) -> None:
        """Make the viewer match a declaration, sending only the changes."""
        raise NotImplementedError

    def var(self, name: str) -> None:
        """Select the variable (``v name``)."""
        raise NotImplementedError

    def plot(self, plot_type: str) -> None:
        """Select the plot type (``p type``)."""
        raise NotImplementedError

    def axes(
        self,
        *,
        x: str | None = None,
        y: str | None = None,
        z: str | None = None,
    ) -> None:
        """Select the axis variables (``x``, ``y``, ``z``)."""
        raise NotImplementedError

    def isel(self, **dims: int) -> None:
        """Select dimension indices (``isel dim index``)."""
        raise NotImplementedError

    def sel(self, **dims: Any) -> None:
        """Select dimension values (``sel dim value``)."""
        raise NotImplementedError

    def over(
        self,
        var: str | None,
        plot_type: str | None = None,
        *,
        layer: int = 2,
    ) -> None:
        """Draw (or with ``None`` remove) an overlaid layer (``over ...``)."""
        raise NotImplementedError

    def set(self, **kwargs: Any) -> None:
        """Apply a keyword line (``key=value, ...``)."""
        raise NotImplementedError

    def delete(self, *names: str) -> None:
        """Delete keywords (``del name``)."""
        raise NotImplementedError

    def get(self, name: str) -> str:
        """The value of a keyword as the app reports it (``get name``)."""
        raise NotImplementedError

    def savefig(
        self,
        filename: str | os.PathLike[str] | None = None,
        *,
        px_per_unit: int | None = None,
        overwrite: bool | None = None,
    ) -> Path:
        """Save the current figure and return the file."""
        raise NotImplementedError

    def record(
        self,
        filename: str | os.PathLike[str] | None = None,
        *,
        framerate: int | None = None,
        px_per_unit: int | None = None,
        frames: Sequence[int] | None = None,
        overwrite: bool | None = None,
    ) -> Path:
        """Record the animation and return the video file."""
        raise NotImplementedError

    def theme(self, name: str) -> None:
        """Switch the Makie theme (``theme name``)."""
        raise NotImplementedError

    def reset(self) -> None:
        """Reset the plot settings (``reset``)."""
        raise NotImplementedError

    def export(self) -> str:
        """The CLI argument line reproducing the current state."""
        raise NotImplementedError

    def show(self) -> None:
        """Show the figure window."""
        raise NotImplementedError

    def hide(self) -> None:
        """Hide the figure window."""
        raise NotImplementedError

    def png(self) -> bytes:
        """The current figure as PNG bytes."""
        raise NotImplementedError

    def _repr_png_(self) -> bytes:
        return self.png()

    def close(self) -> None:
        """End the session: close the pipe, wait for the app to exit."""
        raise NotImplementedError

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


def sessions() -> list[Session]:
    """Every live session of this process."""
    raise NotImplementedError


def close_all() -> None:
    """Close every live session."""
    raise NotImplementedError
