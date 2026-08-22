"""
The public API against a real application.

These run only where a `cdfviewer` binary resolves (the root conftest
skips them otherwise): locally against a bundle or a source build, and in
the release workflow against the bundle that was just compiled. They are
the check that the wrapper and the app still agree -- on the command
line, on the ``Saved ... to`` lines the returned paths are read from, and
on the REPL vocabulary the session speaks.

Each one starts the app, which costs upwards of ten seconds, so there are
few of them and each covers a whole path.
"""

from __future__ import annotations

import numpy as np
import pytest

import cdfviewer as cv

pytestmark = pytest.mark.binary

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


@pytest.fixture(scope="module")
def dataset(tmp_path_factory):
    """A small NetCDF file: temperature over lon, lat and a short time."""
    netCDF4 = pytest.importorskip("netCDF4")  # noqa: N806
    path = tmp_path_factory.mktemp("data") / "demo.nc"
    with netCDF4.Dataset(path, "w") as ds:
        ds.createDimension("lon", 16)
        ds.createDimension("lat", 12)
        ds.createDimension("time", 4)
        lon = ds.createVariable("lon", "f4", ("lon",))
        lat = ds.createVariable("lat", "f4", ("lat",))
        time = ds.createVariable("time", "f4", ("time",))
        lon[:] = np.linspace(-180, 157.5, 16)
        lat[:] = np.linspace(-75, 75, 12)
        time[:] = np.arange(4)
        lon.units = "degrees_east"
        lat.units = "degrees_north"
        temp = ds.createVariable("temperature", "f4", ("time", "lat", "lon"))
        field = np.cos(np.linspace(0, np.pi, 12))[:, None] * np.ones(16)
        temp[:] = np.stack([field * (1 + 0.1 * t) for t in range(4)])
        temp.units = "degC"
        temp.long_name = "Air temperature"
    return path


def test_savefig_writes_the_png_it_returns(dataset, tmp_path):
    """`savefig` renders headlessly and hands back the file it wrote."""
    out = tmp_path / "temperature.png"
    result = cv.savefig(
        dataset,
        var="temperature",
        x="lon",
        y="lat",
        plot_type="heatmap",
        kwargs={"colormap": "balance", "title": "Air temperature"},
        filename=out,
        px_per_unit=1,
    )
    # The path comes from the app's "Saved figure to" line, not from the
    # argument -- so this also checks that the two still agree.
    assert isinstance(result, cv.Figure)
    assert result.path == out
    assert result.path.is_absolute()
    assert result.read_bytes()[:8] == PNG_MAGIC


def test_savefig_without_a_filename_reports_where_it_saved(
    dataset, tmp_path, monkeypatch
):
    """Without a filename the app names the file and says which."""
    monkeypatch.chdir(tmp_path)
    result = cv.savefig(
        dataset, var="temperature", x="lon", y="lat", plot_type="heatmap"
    )
    assert result.path.is_absolute()
    assert result.read_bytes()[:8] == PNG_MAGIC


def test_record_writes_the_video_it_returns(dataset, tmp_path):
    """`record` sweeps the animated dimension and returns the video."""
    out = tmp_path / "temperature.mp4"
    result = cv.record(
        dataset,
        var="temperature",
        x="lon",
        y="lat",
        plot_type="heatmap",
        ani_dim="time",
        filename=out,
        framerate=5,
        frames=(1, 3),  # 1-based and inclusive: three of the four steps
    )
    assert isinstance(result, cv.Animation)
    assert result.path == out
    assert result.path.stat().st_size > 0


def test_command_is_the_line_that_would_run(dataset):
    """`command` names the binary and the options, and runs nothing."""
    cmd = cv.command(
        dataset,
        var="temperature",
        x="lon",
        y="lat",
        plot_type="heatmap",
        savefig=True,
        filename="out.png",
    )
    assert cmd[0].endswith("cdfviewer")
    assert str(dataset) in cmd
    assert "--savefig" in cmd
    shell = cmd.shell
    assert shell.startswith(cmd[0])
    assert "-p heatmap" in shell
    # Nothing was run: no output file, and the binary is still just a path.
    assert not (dataset.parent / "out.png").exists()


def test_session_takes_a_keyword_and_saves(dataset, tmp_path):
    """A live viewer accepts a setting, reports it back, and saves a PNG."""
    session = cv.Session(
        dataset,
        var="temperature",
        x="lon",
        y="lat",
        plot_type="heatmap",
        visible=False,
        no_summary=True,
    )
    try:
        assert session.alive
        assert session.pid > 0

        session.set(colormap="viridis")
        assert "viridis" in session.get("colormap")

        session.isel(time=2)
        out = session.savefig(tmp_path / "session.png")
        assert out.path == tmp_path / "session.png"
        assert out.read_bytes()[:8] == PNG_MAGIC

        assert session.png()[:8] == PNG_MAGIC
    finally:
        session.close()
    assert not session.alive
