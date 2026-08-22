"""``python -m cdfviewer``: the management subcommands."""

from __future__ import annotations

import platform
import sys
from pathlib import Path

import pytest

from cdfviewer import __main__, _binary
from cdfviewer._errors import CDFViewerError
from cdfviewer._version import __version__


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


# ----------------------------------------------------------- install ----
def test_install_prints_where_the_bundle_went(monkeypatch, capsys):
    calls = []

    def _install(version=None, *, force=False):
        calls.append((version, force))
        return Path("/cache/cdfviewer/bin/cdfviewer")

    monkeypatch.setattr(_binary, "install", _install)
    assert __main__.main(["install"]) == 0
    assert calls == [(None, False)]
    assert capsys.readouterr().out == "/cache/cdfviewer/bin/cdfviewer\n"


def test_install_takes_a_version_and_force(monkeypatch, capsys):
    calls = []

    def _install(version=None, *, force=False):
        calls.append((version, force))
        return Path("/cache/cdfviewer")

    monkeypatch.setattr(_binary, "install", _install)
    assert __main__.main(["install", "--version", "2000.1.0", "--force"]) == 0
    assert calls == [("2000.1.0", True)]
    capsys.readouterr()


def test_install_reports_a_failure(monkeypatch, capsys):
    def _install(version=None, *, force=False):  # noqa: ARG001
        raise CDFViewerError("the download failed")

    monkeypatch.setattr(_binary, "install", _install)
    assert __main__.main(["install"]) == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "the download failed" in captured.err


# ------------------------------------------------------------- which ----
def test_which_prints_the_binary(
    fake_binary, fake_config, monkeypatch, capsys
):
    fake_config(version=__version__)
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    assert __main__.main(["which"]) == 0
    assert capsys.readouterr().out == f"{fake_binary}\n"


@pytest.mark.usefixtures("no_candidates", "on_linux")
def test_which_without_a_binary(capsys):
    assert __main__.main(["which"]) == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "no cdfviewer binary found" in captured.err


# ------------------------------------------------------------- prune ----
def test_prune_lists_what_it_removed(cache_dir, capsys):
    for name in (__version__, "2000.1.0"):
        (cache_dir / name).mkdir(parents=True)
    assert __main__.main(["prune"]) == 0
    assert capsys.readouterr().out == f"removed {cache_dir / '2000.1.0'}\n"
    assert (cache_dir / __version__).is_dir()


def test_prune_with_nothing_to_remove(capsys):
    assert __main__.main(["prune"]) == 0
    assert capsys.readouterr().out == "nothing to remove\n"


# --------------------------------------------------------- uninstall ----
def test_uninstall_removes_the_current_bundle(cache_dir, capsys):
    (cache_dir / __version__ / "cdfviewer").mkdir(parents=True)
    assert __main__.main(["uninstall"]) == 0
    assert not (cache_dir / __version__).exists()
    assert f"cdfviewer {__version__}" in capsys.readouterr().out


def test_uninstall_takes_a_version(cache_dir, capsys):
    (cache_dir / "2000.1.0").mkdir(parents=True)
    assert __main__.main(["uninstall", "--version", "2000.1.0"]) == 0
    assert not (cache_dir / "2000.1.0").exists()
    assert "cdfviewer 2000.1.0" in capsys.readouterr().out


# ---------------------------------------------------------- argparse ----
def test_without_a_subcommand(capsys):
    with pytest.raises(SystemExit) as exit_info:
        __main__.main([])
    assert exit_info.value.code == 2
    assert "usage:" in capsys.readouterr().err


def test_help(capsys):
    with pytest.raises(SystemExit) as exit_info:
        __main__.main(["--help"])
    assert exit_info.value.code == 0
    out = capsys.readouterr().out
    for command in ("install", "which", "prune", "uninstall"):
        assert command in out


def test_version(capsys):
    with pytest.raises(SystemExit) as exit_info:
        __main__.main(["--version"])
    assert exit_info.value.code == 0
    assert capsys.readouterr().out == f"cdfviewer {__version__}\n"
