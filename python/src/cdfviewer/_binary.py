"""
Finding the ``cdfviewer`` binary, and fetching one when there is none.

Work package B (stubs). Resolution order: `configure(binary=...)` /
``CDFVIEWER_BIN``, then ``cdfviewer`` on ``PATH`` (skipping this
package's own launcher), then the managed bundle in the cache
directory, downloaded on first use.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from ._version import __version__

if TYPE_CHECKING:  # pragma: no cover
    from pathlib import Path

ASSET = "cdfviewer-linux-x86_64.tar.zst"
RELEASES = "https://github.com/Gordi42/CDFViewer.jl/releases/download"


def release_url(version: str, name: str) -> str:
    """The download URL of asset ``name`` of release ``v<version>``."""
    raise NotImplementedError


def supported_platform() -> bool:
    """Whether a prebuilt bundle exists for this machine (Linux x86_64)."""
    raise NotImplementedError


def candidates_on_path() -> list[Path]:
    """Every ``cdfviewer`` on ``PATH`` that is not a Python script."""
    raise NotImplementedError


def managed_path(version: str = __version__) -> Path:
    """Where the managed bundle of ``version`` puts its executable."""
    raise NotImplementedError


def resolve(*, download: bool = True) -> Path:
    """
    The binary to run.

    Raises
    ------
    CDFViewerError
        When nothing resolves: with ``download=False``, on an unsupported
        platform, or when the download fails.
    """
    raise NotImplementedError


def installed_version(binary: Path) -> str | None:
    """The version ``binary --version`` reports, or None if it has none."""
    raise NotImplementedError


def check_version(binary: Path) -> None:
    """Warn once per process when ``binary`` is not this package's version."""
    raise NotImplementedError


def download(url: str, dest: Path, *, sha256: str | None = None) -> None:
    """Fetch ``url`` to ``dest``, verifying ``sha256`` when given."""
    raise NotImplementedError


def extract(tarball: Path, dest: Path) -> None:
    """Unpack a ``.tar.zst`` bundle into ``dest`` with ``tar --zstd``."""
    raise NotImplementedError


def install(version: str | None = None, *, force: bool = False) -> Path:
    """Download and unpack the bundle of ``version`` (default: this one)."""
    raise NotImplementedError


def which() -> Path | None:
    """The binary `resolve` would use without downloading, or None."""
    raise NotImplementedError


def prune() -> list[Path]:
    """Delete every managed bundle but the current version's."""
    raise NotImplementedError


def uninstall(version: str | None = None) -> None:
    """Delete the managed bundle of ``version`` (default: this one)."""
    raise NotImplementedError
