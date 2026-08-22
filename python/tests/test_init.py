import re
from pathlib import Path

import pytest

import cdfviewer

PROJECT_TOML = Path(__file__).resolve().parents[2] / "Project.toml"


@pytest.mark.parametrize("name", cdfviewer.__all__)
def test_public_name_is_exported(name):
    assert getattr(cdfviewer, name) is not None


def test_version_matches_the_app():
    match = re.search(
        r'^version = "([^"]+)"', PROJECT_TOML.read_text(), re.MULTILINE
    )
    assert match is not None
    assert cdfviewer.__version__ == match.group(1)
