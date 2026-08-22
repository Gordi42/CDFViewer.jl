"""The console script hands the process over to the binary."""

from __future__ import annotations

import os
import sys

import pytest

from cdfviewer import _binary, _launcher
from cdfviewer._errors import CDFViewerError
from cdfviewer._version import __version__


@pytest.fixture
def execv(monkeypatch):
    """`os.execv` recorded instead of performed."""
    calls = []
    monkeypatch.setattr(os, "execv", lambda path, argv: calls.append(
        (path, argv)
    ))
    return calls


def test_launcher_execs_the_binary(
    fake_binary, fake_config, execv, monkeypatch
):
    fake_config(version=__version__)
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    monkeypatch.setattr(sys, "argv", ["cdfviewer", "data.nc", "-v", "t"])
    _launcher.main()
    assert execv == [
        (str(fake_binary), [str(fake_binary), "data.nc", "-v", "t"])
    ]


def test_launcher_passes_no_arguments(
    fake_binary, fake_config, execv, monkeypatch
):
    fake_config(version=__version__)
    monkeypatch.setenv("PATH", str(fake_binary.parent))
    monkeypatch.setattr(sys, "argv", ["cdfviewer"])
    _launcher.main()
    assert execv == [(str(fake_binary), [str(fake_binary)])]


def test_launcher_reports_a_failed_resolve(monkeypatch, capsys):
    def _fail(*, download: bool = True):  # noqa: ARG001
        raise CDFViewerError("no cdfviewer binary found")

    monkeypatch.setattr(_binary, "resolve", _fail)
    with pytest.raises(SystemExit) as exit_info:
        _launcher.main()
    assert exit_info.value.code == 1
    assert "no cdfviewer binary found" in capsys.readouterr().err
