"""
Process-wide settings: the binary to use, the temp and the cache directory.

Each setting is taken from, in this order: what `configure()` was given,
the environment variable, the default.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:  # pragma: no cover
    from types import EllipsisType

ENV_BIN: Final = "CDFVIEWER_BIN"
ENV_TMPDIR: Final = "CDFVIEWER_TMPDIR"
ENV_CACHE: Final = "CDFVIEWER_CACHE"

_settings: dict[str, Path | None] = {
    "binary": None,
    "tmpdir": None,
    "cache_dir": None,
}


def _as_path(value: str | os.PathLike[str] | None) -> Path | None:
    return None if value is None else Path(value).expanduser()


def configure(
    *,
    binary: str | os.PathLike[str] | EllipsisType | None = ...,
    tmpdir: str | os.PathLike[str] | EllipsisType | None = ...,
    cache_dir: str | os.PathLike[str] | EllipsisType | None = ...,
) -> None:
    """
    Set package-wide options for this process.

    A setting that is not passed is left as it is; ``None`` clears it, so
    the environment variable or the default applies again.

    Parameters
    ----------
    binary : str | PathLike | None, optional
        The ``cdfviewer`` executable to run, beating ``CDFVIEWER_BIN``
        and the search on ``PATH``.
    tmpdir : str | PathLike | None, optional
        Where in-memory datasets are written before the app opens them,
        beating ``CDFVIEWER_TMPDIR`` and the system temp directory.
    cache_dir : str | PathLike | None, optional
        Where managed bundles are stored, beating ``CDFVIEWER_CACHE`` and
        ``~/.cache/cdfviewer``.
    """
    if binary is not ...:
        _settings["binary"] = _as_path(binary)
    if tmpdir is not ...:
        _settings["tmpdir"] = _as_path(tmpdir)
    if cache_dir is not ...:
        _settings["cache_dir"] = _as_path(cache_dir)


def reset() -> None:
    """Forget everything `configure()` was given."""
    for key in _settings:
        _settings[key] = None


def _configured_or_env(key: str, env: str) -> Path | None:
    configured = _settings[key]
    if configured is not None:
        return configured
    return _as_path(os.environ.get(env) or None)


def binary_override() -> Path | None:
    """The binary named by `configure()` or ``CDFVIEWER_BIN``, if any."""
    return _configured_or_env("binary", ENV_BIN)


def tmpdir() -> Path:
    """The directory in-memory datasets are written to."""
    return _configured_or_env("tmpdir", ENV_TMPDIR) or Path(
        tempfile.gettempdir()
    )


def cache_dir() -> Path:
    """The directory managed bundles live in."""
    configured = _configured_or_env("cache_dir", ENV_CACHE)
    if configured is not None:
        return configured
    xdg = os.environ.get("XDG_CACHE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".cache"
    return base / "cdfviewer"
