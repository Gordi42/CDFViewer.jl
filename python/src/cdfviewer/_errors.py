"""The exception and the warning category the package raises."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Sequence

_TAIL_LINES = 20


class CDFViewerError(RuntimeError):

    """
    The app failed, or reported an error and carried on.

    Raised on a non-zero exit of the binary, on an ``Error:`` log record
    in its output, and on protocol failures of a session (a prompt that
    never comes). The message ends with the last lines of the app's
    output, so a traceback is readable on its own.

    Parameters
    ----------
    message : str
        What went wrong, in one sentence.
    returncode : int | None, optional
        The exit code of the binary, when it exited (default: None).
    argv : Sequence[str] | None, optional
        The command line that was run (default: None).
    output : str, optional
        The app's combined stdout/stderr (default: "").
    """

    def __init__(
        self,
        message: str,
        *,
        returncode: int | None = None,
        argv: Sequence[str] | None = None,
        output: str = "",
    ) -> None:
        self.message = message
        self.returncode = returncode
        self.argv = list(argv) if argv is not None else None
        self.output = output
        super().__init__(self._full_message())

    def _full_message(self) -> str:
        lines = [line for line in self.output.splitlines() if line.strip()]
        if not lines:
            return self.message
        tail = "\n".join(lines[-_TAIL_LINES:])
        return f"{self.message}\nOutput of cdfviewer (last lines):\n{tail}"


class CDFViewerWarning(UserWarning):

    """
    The app warned, or the package has something to say about its setup.

    Carries the app's ``Warning:`` log records, a version mismatch between
    the package and a binary found on ``PATH``, and the fallback from a
    complex variable to its real part.
    """
