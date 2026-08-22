"""
Shared fixtures: a fake binary on PATH, a local HTTP server, config resets.

The fake binary (``fake_cdfviewer.py``) stands in for the app so the
whole package is tested without a bundle; tests marked ``binary`` run
against a real one and are skipped when none resolves.
"""

from __future__ import annotations

import http.server
import json
import os
import stat
import sys
import threading
from functools import partial
from pathlib import Path
from types import SimpleNamespace

import pytest

from cdfviewer import _binary, _config
from cdfviewer._errors import CDFViewerError

FAKE_SOURCE = Path(__file__).parent / "fake_cdfviewer.py"
# the binary tests are an explicit opt-in: whatever `cdfviewer` happens to
# be on PATH is not what they should silently run against
BINARY_FOR_TESTS = os.environ.get(_config.ENV_BIN)


@pytest.fixture(autouse=True)
def _clean_config(monkeypatch):
    """No configure() state and no CDFVIEWER_* variables leak in or out."""
    for name in (_config.ENV_BIN, _config.ENV_TMPDIR, _config.ENV_CACHE):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.delenv("CDFVIEWER_FAKE_CONFIG", raising=False)
    _config.reset()
    yield
    _config.reset()


@pytest.fixture
def fake_binary(tmp_path, monkeypatch) -> Path:
    """A ``cdfviewer`` on PATH that is the fake, as an executable script."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    target = bin_dir / "cdfviewer"
    target.write_text(f"#!{sys.executable}\n" + FAKE_SOURCE.read_text())
    target.chmod(target.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv(
        "PATH", f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"
    )
    return target


@pytest.fixture
def fake_config(tmp_path, monkeypatch):
    """A function writing the fake binary's JSON configuration."""

    def _set(**options) -> Path:
        path = tmp_path / "fake_config.json"
        path.write_text(json.dumps(options))
        monkeypatch.setenv("CDFVIEWER_FAKE_CONFIG", str(path))
        return path

    return _set


@pytest.fixture
def resolve_fake(fake_binary, monkeypatch) -> Path:
    """`_binary.resolve` answering with the fake binary."""

    def _resolve(*, download: bool = True) -> Path:  # noqa: ARG001
        return fake_binary

    monkeypatch.setattr(_binary, "resolve", _resolve)
    return fake_binary


@pytest.fixture
def cache_dir(tmp_path, monkeypatch) -> Path:
    """A temporary managed-bundle cache."""
    path = tmp_path / "cache"
    monkeypatch.setenv(_config.ENV_CACHE, str(path))
    return path


@pytest.fixture
def data_file(tmp_path) -> Path:
    """A file standing in for a dataset (the fake only checks existence)."""
    path = tmp_path / "data.nc"
    path.write_bytes(b"not really netcdf")
    return path


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args) -> None:
        """Keep the test output clean."""


@pytest.fixture
def http_server(tmp_path):
    """A local HTTP server serving ``.root``; ``.url`` is its base URL."""
    root = tmp_path / "www"
    root.mkdir()
    handler = partial(_QuietHandler, directory=str(root))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield SimpleNamespace(
        root=root, url=f"http://127.0.0.1:{server.server_port}"
    )
    server.shutdown()
    server.server_close()


def pytest_runtest_setup(item):
    """Skip ``binary`` tests unless ``CDFVIEWER_BIN`` names a real binary."""
    if item.get_closest_marker("binary") is None:
        return
    if not BINARY_FOR_TESTS:
        pytest.skip("set CDFVIEWER_BIN to run the binary tests")
    try:
        _binary.resolve(download=False)
    except CDFViewerError as exc:
        pytest.skip(f"CDFVIEWER_BIN does not resolve: {exc}")
