"""
Fixtures for the tests that need a real ``cdfviewer``.

Two things the unit-test fixtures do get in the way here. The root
``conftest`` clears ``CDFVIEWER_BIN`` for every test, which is right when
the fake binary is on ``PATH`` and wrong when the variable is how the
real one was pointed at; and ``filterwarnings = ["error"]`` turns the
once-per-process version warning of a mismatched binary into a failure of
whichever test happens to run first. Both are undone below.
"""

from __future__ import annotations

import os
import warnings

import pytest

import cdfviewer as cv
from cdfviewer import _binary

# Read before any test runs, so the root conftest's delenv cannot hide it.
ENV_BIN = os.environ.get("CDFVIEWER_BIN")


@pytest.fixture(scope="session", autouse=True)
def _warm_resolution():
    """
    Resolve the binary once, before the first test.

    A `PATH` binary whose version differs from the package's warns once
    per process. Spending that warning here keeps it out of the tests,
    which still see every warning the app itself produces.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", cv.CDFViewerWarning)
        _binary.resolve(download=False)


@pytest.fixture(autouse=True)
def _keep_binary_env(_clean_config, monkeypatch):
    """Put ``CDFVIEWER_BIN`` back after the root conftest cleared it."""
    if ENV_BIN is not None:
        monkeypatch.setenv("CDFVIEWER_BIN", ENV_BIN)


@pytest.fixture(autouse=True)
def _no_leftover_sessions():
    """No viewer outlives its test, whatever the test did."""
    yield
    cv.close_all()
