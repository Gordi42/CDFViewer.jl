"""Resolving, downloading and managing the binary."""

from __future__ import annotations

import hashlib
import io
import logging
import os
import platform
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

from cdfviewer import _binary, _config
from cdfviewer._errors import CDFViewerError, CDFViewerWarning
from cdfviewer._version import __version__

FAKE_SOURCE = Path(__file__).parent / "fake_cdfviewer.py"
TAR = shutil.which("tar") or "tar"


# ------------------------------------------------------------ helpers ----
def _script(target: Path) -> Path:
    """The fake binary, as an executable script at ``target``."""
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(f"#!{sys.executable}\n" + FAKE_SOURCE.read_text())
    target.chmod(target.stat().st_mode | stat.S_IXUSR)
    return target


def _shell(target: Path, body: str) -> Path:
    """A tiny executable shell script."""
    target.write_text(f"#!/bin/sh\n{body}\n")
    target.chmod(target.stat().st_mode | stat.S_IXUSR)
    return target


def _tarball(work: Path, dest: Path, *, with_exe: bool = True) -> Path:
    """A bundle: ``cdfviewer/bin/cdfviewer`` in a ``.tar.zst``."""
    stage = work / "stage"
    shutil.rmtree(stage, ignore_errors=True)
    inner = stage / "cdfviewer" / "bin"
    inner.mkdir(parents=True)
    if with_exe:
        _script(inner / "cdfviewer")
    else:
        (inner / "README").write_text("no binary in here\n")
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [TAR, "--zstd", "-cf", str(dest), "-C", str(stage), "cdfviewer"],
        check=True,
    )
    return dest


def _publish(
    server,
    work: Path,
    *,
    version: str = __version__,
    with_exe: bool = True,
    checksum: str = "ok",
) -> Path:
    """Put the release asset, and its ``.sha256``, on the test server."""
    release = server.root / f"v{version}"
    asset = _tarball(work, release / _binary.ASSET, with_exe=with_exe)
    if checksum != "missing":
        digest = (
            hashlib.sha256(asset.read_bytes()).hexdigest()
            if checksum == "ok"
            else "0" * 64
        )
        name = f"{_binary.ASSET}.sha256"
        (release / name).write_text(f"{digest}  {_binary.ASSET}\n")
    return asset


class _Tty(io.StringIO):

    """A stderr that claims to be a terminal."""

    def isatty(self) -> bool:
        return True


# ----------------------------------------------------------- fixtures ----
@pytest.fixture(autouse=True)
def _sandbox_cache(cache_dir):
    """No test in this module may touch the user's real bundle cache."""


@pytest.fixture(autouse=True)
def _forget_version_checks():
    """The once-per-process version warning starts fresh in every test."""
    _binary._version_checked.clear()
    yield
    _binary._version_checked.clear()


@pytest.fixture
def no_candidates(monkeypatch):
    """No ``cdfviewer`` on PATH, whatever the machine really has."""
    monkeypatch.setattr(_binary, "candidates_on_path", list)


@pytest.fixture
def on_linux(monkeypatch):
    """A machine a bundle is built for."""
    monkeypatch.setattr(sys, "platform", "linux")
    monkeypatch.setattr(platform, "machine", lambda: "x86_64")


@pytest.fixture
def elsewhere(monkeypatch):
    """A machine no bundle is built for."""
    monkeypatch.setattr(sys, "platform", "darwin")
    monkeypatch.setattr(platform, "machine", lambda: "arm64")


@pytest.fixture
def releases(http_server, monkeypatch):
    """`release_url` pointing at the local server."""
    monkeypatch.setattr(_binary, "RELEASES", http_server.url)
    return http_server


# -------------------------------------------------------------- urls ----
def test_release_url():
    assert _binary.release_url("1.2.3", "asset.tar.zst") == (
        "https://github.com/Gordi42/CDFViewer.jl/releases/download"
        "/v1.2.3/asset.tar.zst"
    )


@pytest.mark.parametrize(
    ("system", "machine", "expected"),
    [
        ("linux", "x86_64", True),
        ("linux", "AMD64", True),
        ("linux", "aarch64", False),
        ("darwin", "x86_64", False),
    ],
)
def test_supported_platform(monkeypatch, system, machine, expected):
    monkeypatch.setattr(sys, "platform", system)
    monkeypatch.setattr(platform, "machine", lambda: machine)
    assert _binary.supported_platform() is expected


def test_managed_path(cache_dir):
    assert _binary.managed_path("1.2.3") == (
        cache_dir / "1.2.3" / "cdfviewer" / "bin" / "cdfviewer"
    )
    assert _binary.managed_path().parent.parent.parent.name == __version__


# ------------------------------------------------------- PATH search ----
def test_candidates_finds_the_binary(fake_binary, monkeypatch):
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    assert _binary.candidates_on_path() == [fake_binary]


def test_candidates_skips_the_packages_own_launcher(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    launcher = bin_dir / "cdfviewer"
    launcher.write_text(
        f"#!{sys.executable}\n"
        "from cdfviewer._launcher import main\n"
        "main()\n"
    )
    launcher.chmod(launcher.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv("PATH", str(bin_dir))
    assert _binary.candidates_on_path() == []


def test_candidates_skips_a_non_executable_file(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "cdfviewer").write_text("#!/bin/sh\necho hi\n")
    monkeypatch.setenv("PATH", str(bin_dir))
    assert _binary.candidates_on_path() == []


def test_candidates_skips_this_very_process(fake_binary, monkeypatch):
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    monkeypatch.setattr(sys, "argv", [str(fake_binary), "--help"])
    assert _binary.candidates_on_path() == []


def test_candidates_ignores_empty_and_repeated_entries(
    fake_binary, tmp_path, monkeypatch
):
    entries = [
        "",
        str(tmp_path / "gone"),
        str(fake_binary.parent),
        str(fake_binary.parent),
    ]
    monkeypatch.setenv("PATH", os.pathsep.join(entries))
    assert _binary.candidates_on_path() == [fake_binary]


# ---------------------------------------------------------- versions ----
def test_installed_version(fake_binary, fake_config):
    fake_config(version="9.9.9")
    assert _binary.installed_version(fake_binary) == "9.9.9"


def test_installed_version_of_a_missing_binary(tmp_path):
    assert _binary.installed_version(tmp_path / "nope") is None


def test_installed_version_of_a_failing_binary(tmp_path):
    binary = _shell(tmp_path / "bad", "exit 3")
    assert _binary.installed_version(binary) is None


def test_installed_version_of_something_else(tmp_path):
    binary = _shell(tmp_path / "other", "echo some other program")
    assert _binary.installed_version(binary) is None


def test_installed_version_of_a_hanging_binary(tmp_path, monkeypatch):
    def _timeout(*args, **_kwargs):
        raise subprocess.TimeoutExpired(args[0], 20.0)

    monkeypatch.setattr(subprocess, "run", _timeout)
    assert _binary.installed_version(tmp_path / "slow") is None


def test_check_version_is_quiet_when_it_matches(fake_binary, fake_config):
    fake_config(version=__version__)
    _binary.check_version(fake_binary)  # a warning would fail the test


def test_check_version_is_quiet_without_a_version(tmp_path):
    _binary.check_version(_shell(tmp_path / "other", "echo hello"))


def test_check_version_warns_once(fake_binary, fake_config):
    fake_config(version="1.2.3")
    with pytest.warns(CDFViewerWarning, match="cdfviewer 1.2.3"):
        _binary.check_version(fake_binary)
    _binary.check_version(fake_binary)  # a second warning would fail


# ----------------------------------------------------------- resolve ----
def test_resolve_takes_the_environment_override(fake_binary, monkeypatch):
    monkeypatch.setenv(_config.ENV_BIN, str(fake_binary))
    assert _binary.resolve() == fake_binary


def test_resolve_takes_the_configured_binary(fake_binary):
    _config.configure(binary=fake_binary)
    assert _binary.resolve() == fake_binary


def test_resolve_rejects_a_missing_override(tmp_path, monkeypatch):
    monkeypatch.setenv(_config.ENV_BIN, str(tmp_path / "nope"))
    with pytest.raises(CDFViewerError, match="not an executable file"):
        _binary.resolve()


def test_resolve_rejects_a_non_executable_override(tmp_path):
    plain = tmp_path / "plain"
    plain.write_text("#!/bin/sh\n")
    _config.configure(binary=plain)
    with pytest.raises(CDFViewerError, match="CDFVIEWER_BIN"):
        _binary.resolve()


def test_resolve_takes_the_first_binary_on_path(
    fake_binary, fake_config, monkeypatch
):
    fake_config(version=__version__)
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    assert _binary.resolve() == fake_binary


def test_resolve_warns_about_another_version_on_path(
    fake_binary, fake_config, monkeypatch
):
    fake_config(version="1.0.0")
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    with pytest.warns(CDFViewerWarning, match="1.0.0"):
        assert _binary.resolve() == fake_binary


@pytest.mark.usefixtures("no_candidates", "cache_dir")
def test_resolve_takes_the_managed_bundle():
    target = _script(_binary.managed_path())
    assert _binary.resolve(download=False) == target


@pytest.mark.usefixtures("no_candidates", "cache_dir", "on_linux")
def test_resolve_without_download_says_what_to_do():
    with pytest.raises(CDFViewerError, match="CDFVIEWER_BIN") as error:
        _binary.resolve(download=False)
    assert "python -m cdfviewer install" in str(error.value)


@pytest.mark.usefixtures("no_candidates", "cache_dir", "elsewhere")
def test_resolve_on_an_unsupported_platform():
    with pytest.raises(CDFViewerError, match="Linux x86_64 only") as error:
        _binary.resolve()
    assert "darwin arm64" in str(error.value)


@pytest.mark.usefixtures("no_candidates", "cache_dir", "on_linux")
def test_resolve_downloads_the_bundle(releases, tmp_path):
    _publish(releases, tmp_path)
    binary = _binary.resolve()
    assert binary == _binary.managed_path()
    assert os.access(binary, os.X_OK)


# ---------------------------------------------------------- download ----
def test_download_writes_the_file(http_server, tmp_path):
    (http_server.root / "payload.bin").write_bytes(b"cdf" * 1000)
    dest = tmp_path / "out" / "payload.bin"
    digest = hashlib.sha256(b"cdf" * 1000).hexdigest()
    _binary.download(f"{http_server.url}/payload.bin", dest, sha256=digest)
    assert dest.read_bytes() == b"cdf" * 1000
    assert not dest.with_suffix(".bin.part").exists()


def test_download_rejects_a_wrong_checksum(http_server, tmp_path):
    (http_server.root / "payload.bin").write_bytes(b"cdf")
    dest = tmp_path / "payload.bin"
    with pytest.raises(CDFViewerError, match="Checksum mismatch"):
        _binary.download(
            f"{http_server.url}/payload.bin", dest, sha256="0" * 64
        )
    assert not dest.exists()
    assert not dest.with_suffix(".bin.part").exists()


def test_download_reports_a_missing_asset(http_server, tmp_path):
    dest = tmp_path / "payload.bin"
    with pytest.raises(CDFViewerError, match="404"):
        _binary.download(f"{http_server.url}/nothing.bin", dest)
    assert not dest.with_suffix(".bin.part").exists()


def test_download_shows_progress_on_a_terminal(
    http_server, tmp_path, monkeypatch
):
    (http_server.root / "payload.bin").write_bytes(b"x" * 200_000)
    stderr = _Tty()
    monkeypatch.setattr(sys, "stderr", stderr)
    _binary.download(f"{http_server.url}/payload.bin", tmp_path / "p.bin")
    text = stderr.getvalue()
    assert "cdfviewer: downloading" in text
    assert "MiB" in text
    assert "%" in text


def test_progress_without_a_content_length(monkeypatch):
    stderr = _Tty()
    monkeypatch.setattr(sys, "stderr", stderr)
    _binary._progress(2 * 1024 * 1024, 0)
    assert "2.0 MiB" in stderr.getvalue()
    assert "%" not in stderr.getvalue()


# ----------------------------------------------------------- extract ----
def test_extract_unpacks_the_bundle(tmp_path):
    tarball = _tarball(tmp_path, tmp_path / "bundle.tar.zst")
    _binary.extract(tarball, tmp_path / "out")
    assert (tmp_path / "out" / "cdfviewer" / "bin" / "cdfviewer").is_file()


def test_extract_needs_tar(tmp_path, monkeypatch):
    empty = tmp_path / "no-tools"
    empty.mkdir()
    monkeypatch.setenv("PATH", str(empty))
    with pytest.raises(CDFViewerError, match="zstd support"):
        _binary.extract(tmp_path / "bundle.tar.zst", tmp_path / "out")


def test_extract_reports_a_broken_archive(tmp_path):
    tarball = tmp_path / "bundle.tar.zst"
    tarball.write_bytes(b"this is not an archive")
    with pytest.raises(CDFViewerError, match="Unpacking") as error:
        _binary.extract(tarball, tmp_path / "out")
    assert error.value.returncode != 0


# ----------------------------------------------------------- install ----
def test_install_downloads_and_unpacks(releases, cache_dir, tmp_path):
    _publish(releases, tmp_path)
    binary = _binary.install()
    assert binary == _binary.managed_path()
    assert os.access(binary, os.X_OK)
    assert not (cache_dir / _binary.ASSET).exists()
    assert not (cache_dir / f"{_binary.ASSET}.sha256").exists()
    assert not (cache_dir / f"{__version__}.partial").exists()
    result = subprocess.run(
        [str(binary), "--version"], capture_output=True, text=True, check=True
    )
    assert result.stdout.startswith("cdfviewer ")


def test_install_keeps_what_is_there_unless_forced(releases, tmp_path):
    _publish(releases, tmp_path)
    binary = _binary.install()
    binary.write_text("#!/bin/sh\necho stale\n")
    assert _binary.install() == binary
    assert "stale" in binary.read_text()
    assert _binary.install(force=True) == binary
    assert "stale" not in binary.read_text()


def test_install_without_a_checksum_asset_warns(releases, tmp_path, caplog):
    _publish(releases, tmp_path, checksum="missing")
    with caplog.at_level(logging.WARNING, logger="cdfviewer"):
        binary = _binary.install()
    assert binary.is_file()
    assert "without checksum verification" in caplog.text


def test_install_rejects_a_corrupt_download(releases, cache_dir, tmp_path):
    _publish(releases, tmp_path, checksum="wrong")
    with pytest.raises(CDFViewerError, match="Checksum mismatch"):
        _binary.install()
    assert not (cache_dir / _binary.ASSET).exists()
    assert not (cache_dir / f"{_binary.ASSET}.part").exists()


def test_install_cleans_up_after_a_failed_extraction(releases, cache_dir):
    release = releases.root / f"v{__version__}"
    release.mkdir(parents=True)
    (release / _binary.ASSET).write_bytes(b"not an archive")
    digest = hashlib.sha256(b"not an archive").hexdigest()
    (release / f"{_binary.ASSET}.sha256").write_text(
        f"{digest}  {_binary.ASSET}\n"
    )
    with pytest.raises(CDFViewerError, match="Unpacking"):
        _binary.install()
    assert not (cache_dir / f"{__version__}.partial").exists()
    assert not (cache_dir / _binary.ASSET).exists()


def test_install_needs_the_executable_in_the_bundle(releases, tmp_path):
    _publish(releases, tmp_path, with_exe=False)
    with pytest.raises(CDFViewerError, match="has no executable"):
        _binary.install()


def test_install_of_another_version(releases, cache_dir, tmp_path):
    _publish(releases, tmp_path, version="2000.1.0")
    assert _binary.install("2000.1.0") == _binary.managed_path("2000.1.0")
    assert (cache_dir / "2000.1.0").is_dir()


@pytest.mark.usefixtures("elsewhere", "cache_dir")
def test_install_on_an_unsupported_platform():
    with pytest.raises(CDFViewerError, match="Linux x86_64 only"):
        _binary.install()


# ------------------------------------------------------- housekeeping ----
def test_which_finds_the_binary(fake_binary, fake_config, monkeypatch):
    fake_config(version=__version__)
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    assert _binary.which() == fake_binary


@pytest.mark.usefixtures("no_candidates", "cache_dir", "on_linux")
def test_which_returns_none():
    assert _binary.which() is None


def test_prune_keeps_the_current_version(cache_dir):
    for name in (__version__, "2000.1.0", "2000.2.0"):
        (cache_dir / name / "cdfviewer").mkdir(parents=True)
    (cache_dir / "note.txt").write_text("not a bundle\n")
    removed = _binary.prune()
    assert [path.name for path in removed] == ["2000.1.0", "2000.2.0"]
    assert (cache_dir / __version__).is_dir()
    assert (cache_dir / "note.txt").exists()


@pytest.mark.usefixtures("cache_dir")
def test_prune_without_a_cache_directory():
    assert _binary.prune() == []


def test_uninstall(cache_dir):
    (cache_dir / __version__ / "cdfviewer").mkdir(parents=True)
    (cache_dir / "2000.1.0").mkdir()
    _binary.uninstall()
    assert not (cache_dir / __version__).exists()
    _binary.uninstall("2000.1.0")
    assert not (cache_dir / "2000.1.0").exists()


def test_uninstall_a_missing_bundle_is_fine(cache_dir):
    _binary.uninstall("2000.1.0")
    assert not cache_dir.exists()


def test_download_reports_an_unreachable_url(tmp_path):
    dest = tmp_path / "payload.bin"
    with pytest.raises(CDFViewerError, match=r"Downloading .* failed"):
        _binary.download("file:///no/such/asset.bin", dest)
    assert not dest.exists()


@pytest.mark.usefixtures("on_linux")
def test_install_passes_on_a_failing_checksum_download(monkeypatch):
    monkeypatch.setattr(_binary, "RELEASES", "file:///no/such/release")
    with pytest.raises(CDFViewerError, match=r"Downloading .* failed"):
        _binary.install()
