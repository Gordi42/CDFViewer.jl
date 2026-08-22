import tempfile
from pathlib import Path

from cdfviewer import _config


def test_defaults_without_anything_set(monkeypatch):
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    assert _config.binary_override() is None
    assert _config.tmpdir() == Path(tempfile.gettempdir())
    assert _config.cache_dir() == Path.home() / ".cache" / "cdfviewer"
    assert _config.embed_limit() == _config.DEFAULT_EMBED_LIMIT


def test_xdg_cache_home_is_honoured(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path))
    assert _config.cache_dir() == tmp_path / "cdfviewer"


def test_environment_variables(monkeypatch, tmp_path):
    monkeypatch.setenv(_config.ENV_BIN, str(tmp_path / "bin" / "cdfviewer"))
    monkeypatch.setenv(_config.ENV_TMPDIR, str(tmp_path / "tmp"))
    monkeypatch.setenv(_config.ENV_CACHE, str(tmp_path / "cache"))
    assert _config.binary_override() == tmp_path / "bin" / "cdfviewer"
    assert _config.tmpdir() == tmp_path / "tmp"
    assert _config.cache_dir() == tmp_path / "cache"


def test_empty_environment_variable_counts_as_unset(monkeypatch):
    monkeypatch.setenv(_config.ENV_BIN, "")
    assert _config.binary_override() is None


def test_configure_beats_the_environment(monkeypatch, tmp_path):
    monkeypatch.setenv(_config.ENV_BIN, "/env/cdfviewer")
    monkeypatch.setenv(_config.ENV_TMPDIR, "/env/tmp")
    monkeypatch.setenv(_config.ENV_CACHE, "/env/cache")
    _config.configure(
        binary=tmp_path / "cdfviewer", tmpdir=tmp_path, cache_dir=tmp_path
    )
    assert _config.binary_override() == tmp_path / "cdfviewer"
    assert _config.tmpdir() == tmp_path
    assert _config.cache_dir() == tmp_path


def test_configure_leaves_unmentioned_settings_alone(tmp_path):
    _config.configure(binary=tmp_path / "a")
    _config.configure(tmpdir=tmp_path)
    assert _config.binary_override() == tmp_path / "a"
    assert _config.tmpdir() == tmp_path


def test_configure_none_clears_a_setting(monkeypatch, tmp_path):
    monkeypatch.setenv(_config.ENV_BIN, "/env/cdfviewer")
    _config.configure(binary=tmp_path / "a")
    _config.configure(binary=None)
    assert _config.binary_override() == Path("/env/cdfviewer")


def test_configure_expands_the_home_directory():
    _config.configure(cache_dir="~/somewhere")
    assert _config.cache_dir() == Path.home() / "somewhere"


def test_the_embed_limit_from_the_environment(monkeypatch):
    monkeypatch.setenv(_config.ENV_EMBED_LIMIT, "42.5")
    assert _config.embed_limit() == 42.5


def test_configure_sets_the_embed_limit(monkeypatch):
    monkeypatch.setenv(_config.ENV_EMBED_LIMIT, "42.5")
    _config.configure(embed_limit=5)
    assert _config.embed_limit() == 5.0
    _config.configure(embed_limit=None)
    assert _config.embed_limit() == 42.5


def test_reset_forgets_everything(tmp_path):
    _config.configure(
        binary=tmp_path, tmpdir=tmp_path, cache_dir=tmp_path, embed_limit=1
    )
    _config.reset()
    assert _config.binary_override() is None
    assert _config.tmpdir() != tmp_path
    assert _config.embed_limit() == _config.DEFAULT_EMBED_LIMIT
