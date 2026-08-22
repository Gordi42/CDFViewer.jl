"""
Finding the ``cdfviewer`` binary, and fetching one when there is none.

Resolution order (`resolve`): `configure(binary=...)` / ``CDFVIEWER_BIN``,
then ``cdfviewer`` on ``PATH`` (skipping this package's own launcher),
then the managed bundle in the cache directory, downloaded on first use.
The management commands behind ``python -m cdfviewer`` live here too:
`install`, `which`, `prune`, `uninstall`.
"""

from __future__ import annotations

import hashlib
import logging
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import urllib.error
import urllib.request
import warnings
from http import HTTPStatus
from pathlib import Path

from . import _config
from ._errors import CDFViewerError, CDFViewerWarning
from ._version import __version__

ASSET = "cdfviewer-linux-x86_64.tar.zst"
RELEASES = "https://github.com/Gordi42/CDFViewer.jl/releases/download"

_EXE = "cdfviewer"
_MACHINES = frozenset({"x86_64", "AMD64"})
_VERSION_TIMEOUT = 20.0
_VERSION_RE = re.compile(r"cdfviewer\s+(\S+)")
_CHUNK = 1 << 16
_HEAD = 1 << 16
_MIB = 1 << 20
_EXEC_BITS = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH

_logger = logging.getLogger("cdfviewer")
_version_checked: set[str] = set()


def release_url(version: str, name: str) -> str:
    """The download URL of asset ``name`` of release ``v<version>``."""
    return f"{RELEASES}/v{version}/{name}"


def supported_platform() -> bool:
    """Whether a prebuilt bundle exists for this machine (Linux x86_64)."""
    return sys.platform == "linux" and platform.machine() in _MACHINES


def _is_own_launcher(path: Path) -> bool:
    """Whether ``path`` is this package's launcher rather than the app."""
    try:
        with path.open("rb") as handle:
            head = handle.read(_HEAD)
    except OSError:  # pragma: no cover - readable by the time we get here
        return False
    return head.startswith(b"#!") and b"cdfviewer._launcher" in head


def _own_argv0() -> Path | None:
    """The script this process was started as, resolved, if there is one."""
    if not sys.argv or not sys.argv[0]:  # pragma: no cover - always set
        return None
    return Path(sys.argv[0]).resolve()


def candidates_on_path() -> list[Path]:
    """
    Every ``cdfviewer`` on ``PATH`` that is not this package's launcher.

    The console script installed by pip is itself a ``cdfviewer`` on
    ``PATH``; running it would recurse, so Python scripts importing
    `cdfviewer._launcher`, and the script this process was started as,
    are skipped.

    Returns
    -------
    list of Path
        The executables, in ``PATH`` order, without duplicates.
    """
    argv0 = _own_argv0()
    found: list[Path] = []
    seen: set[Path] = set()
    for entry in (os.environ.get("PATH") or os.defpath).split(os.pathsep):
        if not entry:
            continue
        candidate = Path(entry) / _EXE
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            continue
        real = candidate.resolve()
        if real in seen or real == argv0:
            continue
        seen.add(real)
        if _is_own_launcher(candidate):
            continue
        found.append(candidate)
    return found


def managed_path(version: str = __version__) -> Path:
    """Where the managed bundle of ``version`` puts its executable."""
    return _config.cache_dir() / version / "cdfviewer" / "bin" / _EXE


def _unsupported_message() -> str:
    """What to do when no bundle is built for this machine."""
    return (
        f"No cdfviewer bundle is built for {sys.platform} "
        f"{platform.machine()} (Linux x86_64 only). Install CDFViewer.jl "
        "and put the `cdfviewer` executable on PATH, or point "
        "CDFVIEWER_BIN=/path/to/cdfviewer at it."
    )


def _not_found_message() -> str:
    """What to do when nothing resolved and nothing may be downloaded."""
    return (
        "No cdfviewer binary found. Install CDFViewer.jl and put the "
        "`cdfviewer` executable on PATH, point "
        "CDFVIEWER_BIN=/path/to/cdfviewer at it, or run "
        "`python -m cdfviewer install` to download the bundle."
    )


def resolve(*, download: bool = True) -> Path:
    """
    The binary to run.

    Parameters
    ----------
    download : bool, optional
        Whether a missing managed bundle may be fetched
        (default: True).

    Returns
    -------
    Path
        The executable, from `configure(binary=...)` / ``CDFVIEWER_BIN``,
        from ``PATH``, or from the managed bundle.

    Raises
    ------
    CDFViewerError
        When the override is not an executable file, when nothing
        resolves and ``download`` is False or the platform has no
        bundle, or when the download fails.
    """
    override = _config.binary_override()
    if override is not None:
        if not override.is_file() or not os.access(override, os.X_OK):
            raise CDFViewerError(
                f"{override} is not an executable file (from "
                f"{_config.ENV_BIN} or configure(binary=...))."
            )
        return override
    candidates = candidates_on_path()
    if candidates:
        check_version(candidates[0])
        return candidates[0]
    managed = managed_path()
    if managed.is_file():
        return managed
    if not supported_platform():
        raise CDFViewerError(_unsupported_message())
    if not download:
        raise CDFViewerError(_not_found_message())
    return install()


def installed_version(binary: Path) -> str | None:
    """
    The version ``binary --version`` reports, or None if it has none.

    Parameters
    ----------
    binary : Path
        The executable to ask.

    Returns
    -------
    str or None
        The version string, or None when the call fails, times out or
        prints something other than ``cdfviewer <version>``.
    """
    try:
        result = subprocess.run(
            [str(binary), "--version"],
            capture_output=True,
            timeout=_VERSION_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    match = _VERSION_RE.match(result.stdout.decode(errors="replace").strip())
    return match.group(1) if match else None


def check_version(binary: Path) -> None:
    """
    Warn once per process when ``binary`` is not this package's version.

    A binary of another version is used anyway (it may well be the one
    the user wants); a binary without a ``--version`` flag is too old to
    tell and stays silent.

    Parameters
    ----------
    binary : Path
        The executable to check.
    """
    key = str(binary)
    if key in _version_checked:
        return
    _version_checked.add(key)
    version = installed_version(binary)
    if version is None or version == __version__:
        return
    warnings.warn(
        f"{binary} is cdfviewer {version}, but this package is "
        f"{__version__}. Using it anyway.",
        CDFViewerWarning,
        stacklevel=2,
    )


def _progress(done: int, total: int) -> None:
    """Overwrite one line on stderr with what has arrived so far."""
    line = f"\r  {done / _MIB:7.1f} MiB"
    if total > 0:
        line += f" of {total / _MIB:.1f} MiB ({100 * done // total} %)"
    sys.stderr.write(line)
    sys.stderr.flush()


def download(url: str, dest: Path, *, sha256: str | None = None) -> None:
    """
    Fetch ``url`` to ``dest``, verifying ``sha256`` when given.

    The bytes go to ``<dest>.part`` first and are renamed only once they
    are complete and verified. With stderr on a terminal, a notice and a
    progress line are printed there.

    Parameters
    ----------
    url : str
        What to fetch.
    dest : Path
        Where to put it; the parent directory is created.
    sha256 : str or None, optional
        The expected hex digest of the file (default: None, unchecked).

    Raises
    ------
    CDFViewerError
        When the transfer fails or the digest does not match.
    """
    part = dest.with_suffix(dest.suffix + ".part")
    dest.parent.mkdir(parents=True, exist_ok=True)
    _logger.info("Downloading %s", url)
    tty = sys.stderr.isatty()
    if tty:
        sys.stderr.write(f"cdfviewer: downloading {url}\n")
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(url) as response:  # noqa: S310
            total = int(response.headers.get("Content-Length") or 0)
            done = 0
            with part.open("wb") as out:
                while chunk := response.read(_CHUNK):
                    out.write(chunk)
                    digest.update(chunk)
                    done += len(chunk)
                    if tty:
                        _progress(done, total)
    except OSError as exc:
        part.unlink(missing_ok=True)
        if isinstance(exc, urllib.error.HTTPError):
            exc.close()
        raise CDFViewerError(f"Downloading {url} failed: {exc}") from exc
    finally:
        if tty:
            sys.stderr.write("\n")
    if sha256 is not None and digest.hexdigest() != sha256.strip().lower():
        part.unlink(missing_ok=True)
        raise CDFViewerError(
            f"Checksum mismatch for {url}: expected {sha256}, got "
            f"{digest.hexdigest()}. The download was deleted."
        )
    part.replace(dest)


def extract(tarball: Path, dest: Path) -> None:
    """
    Unpack a ``.tar.zst`` bundle into ``dest`` with ``tar --zstd``.

    Parameters
    ----------
    tarball : Path
        The archive to unpack.
    dest : Path
        The directory to unpack into; created when missing.

    Raises
    ------
    CDFViewerError
        When ``tar`` is missing, has no zstd support, or fails.
    """
    dest.mkdir(parents=True, exist_ok=True)
    argv = ["tar", "--zstd", "-xf", str(tarball), "-C", str(dest)]
    hint = (
        "Unpacking the bundle needs `tar` with zstd support (GNU tar "
        ">= 1.31 and the zstd program)."
    )
    try:
        result = subprocess.run(argv, capture_output=True, check=False)
    except OSError as exc:
        raise CDFViewerError(f"{hint} Running tar failed: {exc}") from exc
    if result.returncode != 0:
        raise CDFViewerError(
            f"Unpacking {tarball} failed. {hint}",
            returncode=result.returncode,
            argv=argv,
            output=result.stderr.decode(errors="replace"),
        )


def _fetch_checksum(version: str, cache: Path) -> str | None:
    """The expected digest of the asset, or None when there is none."""
    name = f"{ASSET}.sha256"
    path = cache / name
    try:
        download(release_url(version, name), path)
    except CDFViewerError as exc:
        cause = exc.__cause__
        status = (
            cause.code if isinstance(cause, urllib.error.HTTPError) else None
        )
        if status != HTTPStatus.NOT_FOUND:
            raise
        _logger.warning(
            "Release v%s has no %s asset; installing without checksum "
            "verification.",
            version,
            name,
        )
        return None
    fields = path.read_text().split()
    path.unlink(missing_ok=True)
    return fields[0] if fields else None


def install(version: str | None = None, *, force: bool = False) -> Path:
    """
    Download and unpack the bundle of ``version`` (default: this one).

    Parameters
    ----------
    version : str or None, optional
        The release to install (default: None, this package's version).
    force : bool, optional
        Whether to download again when the bundle is already there
        (default: False).

    Returns
    -------
    Path
        The executable of the installed bundle.

    Raises
    ------
    CDFViewerError
        On an unsupported platform, a failed or corrupt download, a
        failed extraction, or a bundle without the executable.
    """
    version = version or __version__
    if not supported_platform():
        raise CDFViewerError(_unsupported_message())
    target = managed_path(version)
    if target.is_file() and not force:
        return target
    cache = _config.cache_dir()
    cache.mkdir(parents=True, exist_ok=True)
    tarball = cache / ASSET
    expected = _fetch_checksum(version, cache)
    download(release_url(version, ASSET), tarball, sha256=expected)
    staging = cache / f"{version}.partial"
    shutil.rmtree(staging, ignore_errors=True)
    try:
        extract(tarball, staging)
    except CDFViewerError:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    finally:
        tarball.unlink(missing_ok=True)
    final = cache / version
    if final.exists():
        shutil.rmtree(final)
    staging.replace(final)
    if not target.is_file():
        raise CDFViewerError(
            f"The bundle of v{version} has no executable at {target}."
        )
    target.chmod(target.stat().st_mode | _EXEC_BITS)
    _logger.info("Installed cdfviewer %s in %s", version, final)
    return target


def which() -> Path | None:
    """The binary `resolve` would use without downloading, or None."""
    try:
        return resolve(download=False)
    except CDFViewerError:
        return None


def prune() -> list[Path]:
    """
    Delete every managed bundle but the current version's.

    Returns
    -------
    list of Path
        The directories that were removed, in name order.
    """
    cache = _config.cache_dir()
    if not cache.is_dir():
        return []
    removed = []
    for entry in sorted(cache.iterdir()):
        if entry.is_dir() and entry.name != __version__:
            shutil.rmtree(entry)
            _logger.info("Removed %s", entry)
            removed.append(entry)
    return removed


def uninstall(version: str | None = None) -> None:
    """
    Delete the managed bundle of ``version`` (default: this one).

    Parameters
    ----------
    version : str or None, optional
        The release to remove (default: None, this package's version).
        A bundle that is not installed is not an error.
    """
    target = _config.cache_dir() / (version or __version__)
    if target.is_dir():
        shutil.rmtree(target)
        _logger.info("Removed %s", target)
