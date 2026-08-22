"""`Session` against the fake binary: protocol, vocabulary, reuse, lifetime."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from cdfviewer import _config, _data, _session
from cdfviewer._errors import CDFViewerError, CDFViewerWarning
from cdfviewer._format import sym
from cdfviewer._output import Animation, Figure
from cdfviewer._session import PROMPT, Session, close_all, sessions

PNG_MAGIC = b"\x89PNG"

pytestmark = pytest.mark.usefixtures("resolve_fake")


class InMemory:

    """Stands in for an xarray object; `_data.is_in_memory` says yes."""


class Temp:

    """A stand-in for `_data.TempDataset` that counts its cleanups."""

    def __init__(self, path, var=None):
        self.path = path
        self.var = var
        self.cleaned = 0

    def cleanup(self):
        self.cleaned += 1


@pytest.fixture(autouse=True)
def _stub_data(monkeypatch):
    """`_data` is another package's stub here; only identity matters."""
    monkeypatch.setattr(
        _data, "is_in_memory", lambda obj: isinstance(obj, InMemory)
    )


@pytest.fixture(autouse=True)
def _no_leftover_sessions():
    """Every session this module starts is closed, however a test ends."""
    yield
    close_all()
    assert _session._REGISTRY == {}


@pytest.fixture
def sent(monkeypatch):
    """Records every REPL line a session sends, and passes it on."""
    lines: list[str] = []
    original = Session.send

    def spy(self, line, *, timeout=None):
        lines.append(line)
        return original(self, line, timeout=timeout)

    monkeypatch.setattr(Session, "send", spy)
    return lines


@pytest.fixture
def session(data_file):
    """A started session on the fake binary."""
    return Session(data_file)


@pytest.fixture
def other_file(tmp_path):
    """A second dataset, so a second session can be started."""
    path = tmp_path / "other.nc"
    path.write_bytes(b"not really netcdf")
    return path


# ------------------------------------------------------------ startup ----


def test_startup_reaches_the_prompt(resolve_fake, data_file):
    session = Session(data_file, var="t", plot_type="heatmap")
    assert session.alive
    assert session.pid > 0
    assert session._argv[0] == str(resolve_fake)
    assert session._argv[1] == str(data_file)
    assert session._argv[2:] == ["-v", "t", "-p", "heatmap"]
    assert session._buffer == b""


def test_startup_declares_the_selection(data_file):
    session = Session(
        data_file, var="t", x="lon", dims={"time": 2}, kwargs={"xunit": "km"}
    )
    assert session._declared == {
        "var": "t",
        "x": "lon",
        "dims": {"time": 2},
        "kwargs": {"xunit": "km"},
    }


def test_startup_error_record_closes_the_process(data_file, fake_config):
    fake_config(
        records=["┌ Error: dataset is broken", "└ @ CDFViewer.X /x.jl:1"]
    )
    with pytest.raises(CDFViewerError, match="dataset is broken"):
        Session(data_file)
    assert _session._REGISTRY == {}
    assert sessions() == []


def test_startup_warning_record_leaves_the_session_alive(
    data_file, fake_config
):
    fake_config(
        records=["┌ Warning: no time axis", "└ @ CDFViewer.X /x.jl:1"]
    )
    with pytest.warns(CDFViewerWarning, match="no time axis"):
        session = Session(data_file)
    assert session.alive


def test_an_app_that_exits_before_the_prompt_raises(tmp_path):
    with pytest.raises(CDFViewerError, match="exited with code 1") as info:
        Session(tmp_path / "missing.nc")
    assert info.value.returncode == 1
    assert "File or directory not found" in info.value.output


def test_visible_false_hides_the_window(data_file, sent):
    session = Session(data_file, visible=False)
    assert sent == ["hide"]
    assert session.alive


def test_verbose_echoes_the_output(data_file, capfd):
    session = Session(data_file, verbose=True)
    session.send("conf")
    session.close()
    err = capfd.readouterr().err
    assert "Ready." in err
    assert PROMPT in err
    assert "No keyword arguments set." in err


# ---------------------------------------------------------- the pipe ----


def test_send_returns_what_the_app_printed(session):
    assert session.send("hide") == "[ Info: Closed figure window.\n"


def test_send_warns_on_a_warning_record(session):
    with pytest.warns(CDFViewerWarning, match="Unknown command: bogus"):
        session.send("bogus")
    assert session.alive


def test_an_error_record_raises_but_keeps_the_session(session):
    with (
        pytest.warns(CDFViewerWarning, match="reverting: xunit"),
        pytest.raises(CDFViewerError, match="xunit must be one of"),
    ):
        session.send("fail")
    assert session.alive
    assert session.send("hide")


def test_a_slow_answer_times_out(session):
    with pytest.raises(CDFViewerError, match="timeout"):
        session.send("slow 1", timeout=0.25)
    assert session.alive


def test_a_crash_ends_the_session(data_file):
    session = Session(data_file)
    with pytest.raises(CDFViewerError, match="exited with code 3") as info:
        session.send("crash")
    assert info.value.returncode == 3
    assert not session.alive
    assert sessions() == []


def test_sending_to_a_dead_session_raises(data_file):
    session = Session(data_file)
    with pytest.raises(CDFViewerError):
        session.send("crash")
    with pytest.raises(CDFViewerError, match="no longer running"):
        session.send("conf")


def test_a_dead_session_is_replaced(data_file):
    dead = Session(data_file)
    with pytest.raises(CDFViewerError):
        dead.send("crash")
    fresh = Session(data_file)
    assert fresh is not dead
    assert fresh.alive
    assert sessions() == [fresh]


def test_a_closed_input_is_reported(session):
    real = session._proc.stdin

    class Dead:
        closed = True

        def write(self, data):
            raise BrokenPipeError(data)

        def flush(self):
            """Never reached."""

    session._proc.stdin = Dead()
    try:
        with pytest.raises(CDFViewerError, match="closed its input"):
            session.send("conf")
    finally:
        session._proc.stdin = real


# ------------------------------------------------------ the vocabulary ----


def test_var_plot_and_axes(session, sent):
    session.var("u,v")
    session.plot("quiver")
    session.axes(x="lon", z="depth")
    assert sent == ["v u,v", "p quiver", "x lon", "z depth"]


def test_axes_without_arguments_sends_nothing(session, sent):
    session.axes()
    assert sent == []


def test_isel_and_sel(session, sent):
    session.isel(time=3, depth=0)
    session.sel(time="2020-01-01")
    assert sent == ["isel time 3", "isel depth 0", "sel time 2020-01-01"]


def test_over_layers(session, sent):
    session.over("t")
    session.over("u,v", "quiver", layer=3)
    session.over(None, layer=4)
    assert sent == ["over t", "over2 u,v", "over2.p quiver", "over3 off"]


def test_over_refuses_the_base_layer(session):
    with pytest.raises(ValueError, match="1 is the base layer"):
        session.over("t", layer=1)


def test_set_get_and_delete(session, sent):
    session.set(colormap=sym("balance"), xunit="km")
    assert sent == ['colormap=:balance, xunit="km"']
    assert session.get("colormap") == ":balance"
    assert session.get("xunit") == '"km"'
    session.delete("xunit")
    assert session.get("xunit") == ":balance"  # the fake's stand-in default


def test_get_without_an_answer_raises(session):
    session.send = lambda _line, **_kwargs: "[ Info: nothing to report"
    with pytest.raises(CDFViewerError, match="did not report a value"):
        session.get("colormap")


def test_theme_and_reset(session, sent):
    session.theme("dark")
    session.reset()
    assert sent == ["theme dark", "reset"]


def test_show_and_hide(session, sent):
    session.show()
    session.hide()
    assert sent == ["show", "hide"]


def test_export_returns_the_argument_line(data_file):
    session = Session(data_file, var="t", kwargs={"colormap": sym("balance")})
    assert session.export() == "-vt --kwargs='colormap=:balance'"


def test_export_without_an_answer_raises(session):
    session.send = lambda _line, **_kwargs: "nothing at all"
    with pytest.raises(CDFViewerError, match="did not answer the export"):
        session.export()


def test_savefig_writes_and_returns_the_path(session, tmp_path, sent):
    target = tmp_path / "figure.png"
    saved = session.savefig(target, px_per_unit=2, overwrite=True)
    assert isinstance(saved, Figure)
    assert saved.path == target
    assert target.read_bytes().startswith(PNG_MAGIC)
    assert sent == [
        f'savefig filename="{target}", px_per_unit=2, overwrite=true'
    ]


def test_savefig_without_a_filename_uses_the_apps_name(
    data_file, tmp_path, monkeypatch, sent
):
    monkeypatch.chdir(tmp_path)  # the app writes into its own directory
    session = Session(data_file)
    assert session.savefig().path == tmp_path / "cdfviewer.png"
    assert sent == ["savefig"]


def test_savefig_reports_the_apps_error(data_file, fake_config, tmp_path):
    fake_config(fail_save=True)
    session = Session(data_file)
    with pytest.raises(CDFViewerError, match="Saving failed"):
        session.savefig(tmp_path / "figure.png")


def test_a_save_without_a_saved_line_raises(session):
    session.send = lambda _line, **_kwargs: "[ Info: nothing was written"
    with pytest.raises(CDFViewerError, match="did not report where savefig"):
        session.savefig("figure.png")


def test_record_strips_the_progress_bar(session, tmp_path, sent):
    target = tmp_path / "movie.mp4"
    saved = session.record(target, framerate=12, frames=(1, 2, 9))
    assert isinstance(saved, Animation)
    assert saved.path == target
    assert target.read_bytes() == b"fake-mp4"
    assert sent == [f'record filename="{target}", framerate=12, range=1:2:9']


def test_png_returns_bytes_and_cleans_up_on_close(session, tmp_path):
    _config.configure(tmpdir=tmp_path)
    before = sorted(path.name for path in tmp_path.iterdir())
    data = session.png()
    assert data.startswith(PNG_MAGIC)
    assert session._repr_png_() == data
    # the scratch directory stays while the session lives: the app keeps
    # the file name as its save name, and it must keep pointing somewhere
    scratch = [p for p in tmp_path.iterdir() if p.name not in before]
    assert len(scratch) == 1
    assert (scratch[0] / "figure.png").exists()
    session.close()
    assert sorted(path.name for path in tmp_path.iterdir()) == before


# --------------------------------------------------- reuse and apply ----


def test_the_same_dataset_reuses_the_session(data_file, sent):
    first = Session(data_file, var="t")
    sent.clear()
    second = Session(data_file, var="t")
    assert second is first
    assert sent == []  # nothing changed, nothing sent
    assert sessions() == [first]


def test_reuse_sends_only_the_difference(data_file, sent):
    first = Session(
        data_file,
        var="t",
        plot_type="heatmap",
        x="lon",
        dims={"time": 1, "depth": 0},
        kwargs={"colormap": sym("balance"), "xunit": "km"},
        theme="dark",
    )
    sent.clear()
    second = Session(
        data_file,
        var="t",
        plot_type="contour",
        x="lon",
        dims={"time": 4, "depth": 0},
        kwargs={"colormap": sym("viridis")},
        theme="dark",
    )
    assert second is first
    assert sent == [
        "p contour",
        "isel time 4",
        "colormap=:viridis",
        "del xunit",
    ]
    assert first._declared["kwargs"] == {"colormap": sym("viridis")}
    assert first.get("colormap") == ":viridis"
    assert first.get("xunit") == ":balance"  # deleted, so the fake's default


def test_reuse_leaves_what_the_declaration_omits(data_file, sent):
    first = Session(data_file, var="t", theme="dark")
    first.set(linewidth=3)
    sent.clear()
    second = Session(data_file, plot_type="heatmap")
    assert second is first
    assert sent == ["p heatmap"]
    assert first._declared["var"] == "t"
    assert first._declared["theme"] == "dark"
    assert first.get("linewidth") == "3"  # set by hand, so left alone


def test_reuse_applies_axes_ani_dim_and_theme(data_file, sent):
    Session(data_file, var="t")
    sent.clear()
    Session(data_file, y="lat", z="depth", ani_dim="time", theme="black")
    assert sent == ["y lat", "z depth", "pdim time", "theme black"]


def test_reuse_applies_layers(data_file, sent):
    first = Session(data_file, over=["u,v", "t"], over_plot=["quiver"])
    sent.clear()
    Session(data_file, over=["u,v"], over_plot=["arrows"])
    assert sent == ["over.p arrows", "over2 off"]
    assert first._declared["over"] == ["u,v"]


def test_reuse_changes_a_layer_variable_and_its_type(data_file, sent):
    Session(data_file, over=["t"])
    sent.clear()
    Session(data_file, over=["s"], over_plot=["contour"])
    assert sent == ["over s", "over.p contour"]


def test_reuse_sends_nothing_for_what_is_unchanged(data_file, sent):
    Session(
        data_file,
        var="t",
        dims={"time": 1},
        over=["u,v"],
        over_plot=["quiver"],
        kwargs={"xunit": "km"},
    )
    sent.clear()
    Session(
        data_file,
        var="s",
        dims={"time": 1},
        over=["u,v"],
        over_plot=["quiver"],
        kwargs={"xunit": "km"},
    )
    assert sent == ["v s"]  # only the variable moved


def test_apply_refuses_a_foreign_keyword(session):
    with pytest.raises(TypeError, match="not part of a declaration: grid"):
        session.apply(grid="g.nc", var="t")


def test_a_different_dataset_starts_a_second_session(data_file, other_file):
    first = Session(data_file)
    second = Session(other_file)
    assert second is not first
    assert set(sessions()) == {first, second}


def test_use_local_is_part_of_the_key(data_file):
    first = Session(data_file)
    second = Session(data_file, use_local=True)
    assert second is not first


def test_reuse_false_starts_another_viewer(data_file):
    first = Session(data_file)
    second = Session(data_file, reuse=False)
    assert second is not first
    assert first.alive
    assert sessions() == [second]  # the registry now points at the new one
    first.close()  # the old one is only reachable through its name


# ------------------------------------------------------- in-memory ----


def test_in_memory_input_goes_through_a_temporary_file(
    data_file, monkeypatch
):
    obj = InMemory()
    temp = Temp(data_file, var="data")
    seen = {}

    def write_temp(source, *, complex_as="split", var=None):
        seen.update(source=source, complex_as=complex_as, var=var)
        return temp

    monkeypatch.setattr(_data, "write_temp", write_temp)
    session = Session(obj, complex_as="abs")
    assert seen == {"source": obj, "complex_as": "abs", "var": None}
    assert session._argv[1:] == [str(data_file), "-v", "data"]
    assert session._object is obj
    assert Session(obj) is session  # the same object is the same session
    session.close()
    assert temp.cleaned == 1
    session.close()  # idempotent, and the temp file is not cleaned twice
    assert temp.cleaned == 1


def test_another_object_is_another_session(data_file, monkeypatch):
    first_obj, second_obj = InMemory(), InMemory()
    monkeypatch.setattr(
        _data, "write_temp", lambda _source, **_kwargs: Temp(data_file)
    )
    first = Session(first_obj)
    second = Session(second_obj)
    assert second is not first
    assert len(sessions()) == 2


# -------------------------------------------------------- lifetime ----


def test_close_is_idempotent(data_file):
    session = Session(data_file)
    session.close()
    assert not session.alive
    assert sessions() == []
    session.close()


def test_close_kills_an_app_that_will_not_exit(data_file):
    session = Session(data_file)
    real_wait = session._proc.wait
    refused = []

    def wait(timeout=None):
        if not refused:
            refused.append(timeout)
            raise subprocess.TimeoutExpired(cmd="cdfviewer", timeout=timeout)
        return real_wait(timeout=timeout)

    session._proc.wait = wait
    session.close()
    assert refused == [_session._CLOSE_TIMEOUT]
    assert not session.alive


def test_the_context_manager_closes(data_file):
    with Session(data_file) as session:
        assert session.alive
        assert session.send("conf")
    assert not session.alive


def test_sessions_and_close_all(data_file, other_file):
    first, second = Session(data_file), Session(other_file)
    assert set(sessions()) == {first, second}
    close_all()
    assert sessions() == []
    assert not first.alive
    assert not second.alive


def test_save_resolves_a_relative_report_against_the_start_directory(
    data_file, tmp_path, monkeypatch
):
    start = tmp_path / "start"
    start.mkdir()
    monkeypatch.chdir(start)
    session = Session(data_file)
    # moving on after the start changes nothing: the app still sits there
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        _session, "saved_path", lambda _records: Path("demo.png")
    )
    assert session.savefig().path == start / "demo.png"
    assert session.record().path == start / "demo.png"
