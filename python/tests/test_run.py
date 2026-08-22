"""One process per call: `run`, `savefig` and `record`."""

from pathlib import Path

import pytest

from cdfviewer import _config, _data, _run
from cdfviewer._errors import CDFViewerError, CDFViewerWarning
from cdfviewer._logs import Record, parse_records

xr = pytest.importorskip("xarray")
np = pytest.importorskip("numpy")

WARNING_RECORD = ["┌ Warning: careful now", "└ @ CDFViewer.M /x/f.jl:1"]
ERROR_RECORD = ["┌ Error: bad news", "└ @ CDFViewer.M /x/f.jl:1"]


@pytest.fixture
def scratch(tmp_path, monkeypatch) -> Path:
    """Temporary datasets go inside the test's own directory."""
    path = tmp_path / "scratch"
    monkeypatch.setenv(_config.ENV_TMPDIR, str(path))
    return path


def save_argv(binary, data, target, *, record=False):
    """A command line saving ``target``, as `command` would build it."""
    return [
        str(binary),
        str(data),
        "--record" if record else "--savefig",
        "-s",
        f'filename="{target}"',
    ]


def spy_on_run(monkeypatch):
    """Record every argv `run` is called with, and let it run."""
    calls: list[list[str]] = []
    real = _run.run

    def spy(argv, *, verbose=False, check=True):
        calls.append(list(argv))
        return real(argv, verbose=verbose, check=check)

    monkeypatch.setattr(_run, "run", spy)
    return calls


def canned_run(monkeypatch, output):
    """Replace `run` with one that answers ``output`` without a process."""
    calls: list[list[str]] = []

    def fake(argv, *, verbose=False, check=True):  # noqa: ARG001
        calls.append(list(argv))
        return _run.RunResult(0, output, parse_records(output))

    monkeypatch.setattr(_run, "run", fake)
    return calls


# ---------------------------------------------------------------------- run


def test_run_captures_the_output(fake_binary, data_file, tmp_path):
    target = tmp_path / "fig.png"
    result = _run.run(save_argv(fake_binary, data_file, target))
    assert result.returncode == 0
    assert f"[ Info: Saved figure to {target}" in result.output
    assert Record("Info", f"Saved figure to {target}") in result.records
    assert target.exists()


def test_run_accepts_path_objects(fake_binary, data_file, tmp_path):
    target = tmp_path / "fig.png"
    argv = [fake_binary, data_file, "--savefig", "-s", f'filename="{target}"']
    assert _run.run(argv).returncode == 0


def test_run_keeps_the_progress_bar_as_it_was(
    fake_binary, data_file, tmp_path
):
    target = tmp_path / "movie.mp4"
    result = _run.run(save_argv(fake_binary, data_file, target, record=True))
    # text mode would have turned the bar's \r into newlines
    assert "\rRecording 100%" in result.output
    assert result.records[-1].message == f"Saved animation to {target}"


def test_run_is_quiet_by_default(fake_binary, data_file, tmp_path, capsys):
    _run.run(save_argv(fake_binary, data_file, tmp_path / "fig.png"))
    captured = capsys.readouterr()
    assert captured.err == ""
    assert captured.out == ""


def test_run_streams_when_verbose(fake_binary, data_file, tmp_path, capsys):
    target = tmp_path / "movie.mp4"
    argv = save_argv(fake_binary, data_file, target, record=True)
    result = _run.run(argv, verbose=True)
    captured = capsys.readouterr()
    assert captured.err == result.output
    assert "\rRecording 100%" in captured.err


def test_run_raises_on_a_non_zero_exit(
    fake_binary, fake_config, data_file, tmp_path
):
    fake_config(exit_code=3)
    argv = save_argv(fake_binary, data_file, tmp_path / "fig.png")
    with pytest.raises(CDFViewerError) as excinfo:
        _run.run(argv)
    error = excinfo.value
    assert "cdfviewer exited with code 3" in str(error)
    assert error.returncode == 3
    assert error.argv == argv
    assert "Saved figure to" in error.output


def test_run_without_check_reports_the_code(
    fake_binary, fake_config, data_file, tmp_path
):
    fake_config(exit_code=3, records=ERROR_RECORD)
    argv = save_argv(fake_binary, data_file, tmp_path / "fig.png")
    result = _run.run(argv, check=False)
    assert result.returncode == 3
    assert Record("Error", "bad news") in result.records


def test_run_without_a_binary(tmp_path):
    with pytest.raises(CDFViewerError, match="no such file") as excinfo:
        _run.run([str(tmp_path / "nowhere" / "cdfviewer"), "data.nc"])
    assert excinfo.value.returncode is None


# ---------------------------------------------------------- savefig, record


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_returns_the_file_it_saved(data_file, tmp_path):
    target = tmp_path / "out" / "fig.png"
    target.parent.mkdir()
    saved = _run.savefig(data_file, var="temp", filename=target)
    assert saved == target
    assert saved.is_absolute()
    assert saved.read_bytes().startswith(b"\x89PNG")


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_without_a_filename(data_file, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    saved = _run.savefig(data_file)
    assert saved == tmp_path / "cdfviewer.png"
    assert saved.exists()


@pytest.mark.usefixtures("resolve_fake")
def test_record_returns_the_video(data_file, tmp_path):
    saved = _run.record(data_file, ani_dim="time", filename=tmp_path / "a.mp4")
    assert saved == tmp_path / "a.mp4"
    assert saved.read_bytes() == b"fake-mp4"


def test_savefig_passes_selection_and_save_options(
    resolve_fake, data_file, tmp_path, monkeypatch
):
    calls = spy_on_run(monkeypatch)
    target = tmp_path / "fig.png"
    _run.savefig(
        data_file,
        var="temp",
        x="lon",
        kwargs={"colormap": "balance"},
        filename=target,
        px_per_unit=2,
        overwrite=False,
    )
    argv = calls[0]
    assert argv[0] == str(resolve_fake)
    assert argv[1] == str(data_file)
    assert argv[argv.index("-v") + 1] == "temp"
    assert argv[argv.index("-x") + 1] == "lon"
    assert '--kwargs=colormap="balance"' in argv
    assert "--savefig" in argv
    assert "--no-summary" in argv
    assert argv[argv.index("-s") + 1] == (
        f'filename="{target}", px_per_unit=2, overwrite=false'
    )


@pytest.mark.usefixtures("resolve_fake")
def test_record_passes_its_own_save_options(
    data_file, tmp_path, monkeypatch
):
    target = tmp_path / "a.mp4"
    calls = canned_run(monkeypatch, f"[ Info: Saved animation to {target}\n")
    _run.record(
        data_file,
        filename=target,
        framerate=12,
        px_per_unit=2,
        frames=(1, 2, 10),
        overwrite=True,
    )
    argv = calls[0]
    assert "--record" in argv
    assert "--savefig" not in argv
    assert argv[argv.index("-s") + 1] == (
        f'filename="{target}", framerate=12, px_per_unit=2, '
        "range=1:2:10, overwrite=true"
    )


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_hands_verbose_to_run(data_file, tmp_path, capsys):
    _run.savefig(data_file, filename=tmp_path / "fig.png", verbose=True)
    assert "Saved figure to" in capsys.readouterr().err


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_warns_about_warning_records(
    fake_config, data_file, tmp_path
):
    fake_config(records=WARNING_RECORD)
    target = tmp_path / "fig.png"
    with pytest.warns(CDFViewerWarning, match="careful now"):
        saved = _run.savefig(data_file, filename=target)
    assert saved == target


def test_savefig_raises_on_error_records(
    resolve_fake, fake_config, data_file, tmp_path
):
    fake_config(records=ERROR_RECORD)
    target = tmp_path / "fig.png"
    with pytest.raises(CDFViewerError) as excinfo:
        _run.savefig(data_file, filename=target)
    error = excinfo.value
    assert "bad news" in str(error)
    assert error.argv[0] == str(resolve_fake)
    assert "Saved figure to" in error.output
    assert target.exists()  # the app got that far, the file stays


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_needs_a_saved_line(data_file, tmp_path, monkeypatch):
    canned_run(monkeypatch, "[ Info: Ready.\n")
    with pytest.raises(CDFViewerError, match="did not report a saved file"):
        _run.savefig(data_file, filename=tmp_path / "fig.png")


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_reports_a_failed_save(fake_config, data_file, tmp_path):
    fake_config(fail_save=True)
    with pytest.raises(CDFViewerError, match="exited with code 1") as excinfo:
        _run.savefig(data_file, filename=tmp_path / "fig.png")
    assert "Saving failed" in excinfo.value.output


# ------------------------------------------------------------ in-memory data


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_writes_a_data_array_first(scratch, tmp_path, monkeypatch):
    calls = spy_on_run(monkeypatch)
    array = xr.DataArray(np.zeros((2, 3)), name="temp")
    saved = _run.savefig(array, filename=tmp_path / "fig.png")
    assert saved.exists()
    argv = calls[0]
    written = Path(argv[1])
    assert written.parent.parent == scratch
    assert written.name == "dataset.nc"
    assert argv[argv.index("-v") + 1] == "temp"  # the array's own name
    assert not written.exists()  # cleaned up after the process exited
    assert list(scratch.iterdir()) == []


@pytest.mark.usefixtures("resolve_fake", "scratch")
def test_savefig_of_a_dataset_selects_nothing_by_itself(
    tmp_path, monkeypatch
):
    calls = spy_on_run(monkeypatch)
    dataset = xr.Dataset({"a": ("x", np.zeros(3)), "b": ("x", np.ones(3))})
    _run.record(dataset, filename=tmp_path / "a.mp4")
    assert "-v" not in calls[0]


@pytest.mark.usefixtures("resolve_fake", "scratch")
def test_savefig_resolves_a_complex_variable(tmp_path, monkeypatch):
    calls = spy_on_run(monkeypatch)
    dataset = xr.Dataset({"psi": ("x", np.array([1 + 1j, 2 + 0j]))})
    with pytest.warns(CDFViewerWarning, match="'psi' is complex"):
        _run.savefig(dataset, var="psi", filename=tmp_path / "fig.png")
    argv = calls[0]
    assert argv[argv.index("-v") + 1] == "psi_real"


@pytest.mark.usefixtures("resolve_fake")
def test_savefig_passes_complex_as_on(monkeypatch, tmp_path):
    seen = {}

    def fake_write_temp(obj, *, complex_as, var):
        seen.update(obj=obj, complex_as=complex_as, var=var)
        return _data.TempDataset(tmp_path / "data.nc", "psi")

    (tmp_path / "data.nc").write_bytes(b"x")
    monkeypatch.setattr(_data, "write_temp", fake_write_temp)
    canned_run(monkeypatch, f"[ Info: Saved figure to {tmp_path / 'f.png'}\n")
    array = xr.DataArray(np.zeros(3), name="psi")
    _run.savefig(array, var="psi", complex_as="abs")
    assert seen["complex_as"] == "abs"
    assert seen["var"] == "psi"
    assert seen["obj"] is array


@pytest.mark.usefixtures("resolve_fake")
def test_the_temp_dataset_is_cleaned_up_when_the_run_fails(
    monkeypatch, tmp_path
):
    cleaned = []

    class _Temp:
        path = tmp_path / "gone" / "dataset.nc"
        var = "u"

        def cleanup(self):
            cleaned.append(1)

    monkeypatch.setattr(_data, "is_in_memory", lambda obj: True)  # noqa: ARG005
    monkeypatch.setattr(
        _data, "write_temp", lambda obj, **kw: _Temp()  # noqa: ARG005
    )
    with pytest.raises(CDFViewerError, match="exited with code 1"):
        _run.savefig("whatever", filename=tmp_path / "fig.png")
    assert cleaned == [1]
