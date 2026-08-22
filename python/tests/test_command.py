"""The command line of one call, built from Python values."""

import os
import shlex
from pathlib import Path

import pytest

from cdfviewer._command import Command, build_args, command
from cdfviewer._format import sym

# ------------------------------------------------------------- Command ----


def test_command_is_a_list():
    cmd = Command(["cdfviewer", "a.nc"])
    assert isinstance(cmd, list)
    assert cmd == ["cdfviewer", "a.nc"]
    assert cmd[0] == "cdfviewer"
    assert len(cmd) == 2


def test_command_shell_quotes_what_needs_quoting():
    cmd = Command(["/opt/cdf viewer", "a b.nc", '--kwargs=title="hi there"'])
    assert cmd.shell == (
        "'/opt/cdf viewer' 'a b.nc' '--kwargs=title=\"hi there\"'"
    )


@pytest.mark.parametrize(
    "argv",
    [
        ["cdfviewer", "a.nc"],
        ["cdfviewer", "a b.nc", "-v", "t"],
        ["cdfviewer", "--kwargs=title=\"it's here\", colormap=:balance"],
        ["cdfviewer", "--dims=z=0,time=3", "-s", 'filename="my fig.png"'],
        ["cdfviewer", "a$b.nc", "back\\slash.nc", "semi;colon.nc"],
    ],
)
def test_shell_round_trips_through_shlex(argv):
    cmd = Command(argv)
    assert shlex.split(cmd.shell) == list(cmd)


def test_shell_of_a_built_command(resolve_fake, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    cmd = command("a b.nc", kwargs={"title": 'say "hi"'})
    assert shlex.split(cmd.shell) == list(cmd)
    assert cmd.shell.startswith(shlex.quote(str(resolve_fake)))


# ------------------------------------------------------------ the paths ----


def test_a_single_path_is_made_absolute(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("data.nc") == [str(tmp_path / "data.nc")]


def test_an_absolute_path_is_kept(tmp_path):
    assert build_args(str(tmp_path / "data.nc")) == [
        str(tmp_path / "data.nc")
    ]


def test_a_pathlike_is_accepted(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args(Path("data.nc")) == [str(tmp_path / "data.nc")]


def test_a_sequence_of_paths_keeps_its_order(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args(["b.nc", Path("a.nc")])
    assert args == [str(tmp_path / "b.nc"), str(tmp_path / "a.nc")]


def test_a_tuple_of_paths_is_accepted(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args(("a.nc", "b.nc")) == [
        str(tmp_path / "a.nc"),
        str(tmp_path / "b.nc"),
    ]


def test_a_tilde_is_expanded():
    assert build_args("~/data.nc") == [str(Path.home() / "data.nc")]


def test_dots_are_normalised(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("sub/../data.nc") == [str(tmp_path / "data.nc")]


@pytest.mark.parametrize(
    "url",
    [
        "https://example.com/store.zarr",
        "http://example.com/data.nc",
        "s3://bucket/store.zarr",
    ],
)
def test_a_url_is_left_untouched(url, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args(url) == [url]


def test_urls_and_files_can_be_mixed(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args(["https://x/y.nc", "local.nc"])
    assert args == ["https://x/y.nc", str(tmp_path / "local.nc")]


@pytest.mark.parametrize("empty", [[], (), "", ["a.nc", ""]])
def test_no_path_at_all_is_an_error(empty):
    with pytest.raises(ValueError, match="at least one file"):
        build_args(empty)


# --------------------------------------------------------- the CLI order ----


def test_the_full_command_line_in_the_cli_order(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args(
        ["a.nc", "b.nc"],
        var="temp",
        x="lon",
        y="lat",
        z="depth",
        plot_type="heatmap",
        ani_dim="time",
        dims={"z": 0, "time": 3},
        over=["u,v", "salt"],
        over_plot=["quiver"],
        kwargs={"colormap": "balance", "pos": sym("lt")},
        grid="grid.nc",
        theme="dark",
        no_grid_search=True,
        use_local=True,
        menu=True,
        no_summary=True,
        record=True,
        filename="out.mp4",
        framerate=24,
        px_per_unit=2,
        frames=(1, 10),
        overwrite=False,
    )
    assert args == [
        str(tmp_path / "a.nc"),
        str(tmp_path / "b.nc"),
        "-v", "temp",
        "-x", "lon",
        "-y", "lat",
        "-z", "depth",
        "-p", "heatmap",
        "-a", "time",
        "--dims=z=0,time=3",
        "--over", "u,v",
        "--over", "salt",
        "--over-plot", "quiver",
        '--kwargs=colormap="balance", pos=:lt',
        "-g", str(tmp_path / "grid.nc"),
        "--theme", "dark",
        "--no-grid-search",
        "--use-local",
        "--menu",
        "--no-summary",
        "--record",
        "-s",
        'filename="' + str(tmp_path / "out.mp4") + '", framerate=24, '
        "px_per_unit=2, range=1:10, overwrite=false",
    ]


def test_nothing_but_the_path_by_default(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc") == [str(tmp_path / "a.nc")]


@pytest.mark.parametrize(
    ("option", "expected"),
    [
        ({"var": "temp"}, ["-v", "temp"]),
        ({"x": "lon"}, ["-x", "lon"]),
        ({"y": "lat"}, ["-y", "lat"]),
        ({"z": "depth"}, ["-z", "depth"]),
        ({"plot_type": "heatmap"}, ["-p", "heatmap"]),
        ({"ani_dim": "time"}, ["-a", "time"]),
        ({"theme": "dark"}, ["--theme", "dark"]),
        ({"dims": {"z": 0}}, ["--dims=z=0"]),
        ({"over": ["u"]}, ["--over", "u"]),
        ({"kwargs": {"alpha": 0.5}}, ["--kwargs=alpha=0.5"]),
        ({"no_grid_search": True}, ["--no-grid-search"]),
        ({"use_local": True}, ["--use-local"]),
        ({"menu": True}, ["--menu"]),
        ({"no_summary": True}, ["--no-summary"]),
        ({"savefig": True}, ["--savefig"]),
        ({"record": True}, ["--record"]),
    ],
)
def test_one_option_at_a_time(option, expected, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", **option)
    assert args == [str(tmp_path / "a.nc"), *expected]


def test_an_empty_string_option_is_still_passed(tmp_path, monkeypatch):
    # None means "not set"; an empty string is a value the user gave
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc", var="") == [str(tmp_path / "a.nc"), "-v", ""]


@pytest.mark.parametrize(
    "flag",
    ["no_grid_search", "use_local", "menu", "no_summary", "savefig", "record"],
)
def test_a_flag_that_is_off_is_left_out(flag, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc", **{flag: False}) == [str(tmp_path / "a.nc")]


def test_the_grid_is_made_absolute(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", grid=Path("~/grid.nc"))
    assert args[-1] == str(Path.home() / "grid.nc")
    assert args[-2] == "-g"


# --------------------------------------------------------- the overlays ----


def test_over_and_over_plot_come_in_two_runs(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", over=["u", "v", "w"], over_plot=["quiver", "c"])
    assert args[1:] == [
        "--over", "u",
        "--over", "v",
        "--over", "w",
        "--over-plot", "quiver",
        "--over-plot", "c",
    ]


def test_over_plot_alone_is_refused():
    with pytest.raises(ValueError, match="more layers than over"):
        build_args("a.nc", over_plot=["quiver"])


def test_more_over_plot_than_over_is_refused():
    with pytest.raises(ValueError, match="more layers than over"):
        build_args("a.nc", over=["u"], over_plot=["quiver", "contour"])


def test_as_many_over_plot_as_over_is_fine(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", over=["u"], over_plot=["quiver"])
    assert args[1:] == ["--over", "u", "--over-plot", "quiver"]


@pytest.mark.parametrize("name", ["over", "over_plot"])
def test_a_bare_string_of_overlays_is_refused(name):
    # list("temp") would quietly become four one-letter overlays
    options = {"over": ["temp", "salt"], name: "temp"}
    with pytest.raises(TypeError, match="not a single string"):
        build_args("a.nc", **options)


def test_empty_overlays_add_nothing(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", over=[], over_plot=[])
    assert args == [str(tmp_path / "a.nc")]


# ---------------------------------------------------- dims and kwargs ----


def test_an_empty_dims_mapping_adds_nothing(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc", dims={}) == [str(tmp_path / "a.nc")]


def test_an_empty_kwargs_mapping_adds_nothing(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc", kwargs={}) == [str(tmp_path / "a.nc")]


def test_dims_and_kwargs_are_one_argument_each(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args(
        "a.nc", dims={"z": 0, "time": 3}, kwargs={"a": 1, "b": "x"}
    )
    assert args[1] == "--dims=z=0,time=3"
    assert args[2] == '--kwargs=a=1, b="x"'


def test_a_bad_kwargs_value_is_refused():
    with pytest.raises(TypeError, match="cannot write a set"):
        build_args("a.nc", kwargs={"colormap": {"balance"}})


# ------------------------------------------------------ the save options ----


def test_savefig_and_record_exclude_each_other():
    with pytest.raises(ValueError, match="exclude each other"):
        build_args("a.nc", savefig=True, record=True)


@pytest.mark.parametrize(
    ("option", "expected"),
    [
        ({"framerate": 24}, "framerate=24"),
        ({"px_per_unit": 2}, "px_per_unit=2"),
        ({"frames": (1, 2, 10)}, "range=1:2:10"),
        ({"overwrite": True}, "overwrite=true"),
        ({"overwrite": False}, "overwrite=false"),
    ],
)
def test_one_save_option_puts_up_the_s_flag(
    option, expected, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", savefig=True, **option)
    assert args[-2:] == ["-s", expected]


def test_no_save_option_means_no_s_flag(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert build_args("a.nc", savefig=True) == [
        str(tmp_path / "a.nc"),
        "--savefig",
    ]


def test_the_filename_is_made_absolute(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", savefig=True, filename="fig.png")
    assert args[-1] == f'filename="{tmp_path / "fig.png"}"'


def test_the_filename_is_tilde_expanded():
    args = build_args("a.nc", savefig=True, filename=Path("~/fig.png"))
    assert args[-1] == f'filename="{Path.home() / "fig.png"}"'


def test_the_save_options_survive_without_savefig(tmp_path, monkeypatch):
    # a Session start line may carry the defaults for its later `savefig`
    monkeypatch.chdir(tmp_path)
    args = build_args("a.nc", px_per_unit=2)
    assert args == [str(tmp_path / "a.nc"), "-s", "px_per_unit=2"]


def test_a_bad_frames_tuple_is_refused():
    with pytest.raises(TypeError, match="frames must be"):
        build_args("a.nc", record=True, frames=(1, 2, 3, 4))


# ------------------------------------------------------------- command() ----


def test_command_puts_the_resolved_binary_first(
    resolve_fake, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    cmd = command("a.nc")
    assert isinstance(cmd, Command)
    assert cmd[0] == str(resolve_fake)
    assert cmd[1:] == [str(tmp_path / "a.nc")]


def test_command_passes_every_argument_on(resolve_fake, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    options = {
        "var": "temp",
        "x": "lon",
        "y": "lat",
        "z": "depth",
        "plot_type": "heatmap",
        "ani_dim": "time",
        "dims": {"z": 0},
        "over": ["u"],
        "over_plot": ["quiver"],
        "kwargs": {"colormap": "balance"},
        "grid": "grid.nc",
        "theme": "dark",
        "no_grid_search": True,
        "use_local": True,
        "menu": True,
        "no_summary": True,
        "record": True,
        "filename": "out.mp4",
        "framerate": 24,
        "px_per_unit": 2,
        "frames": (1, 10),
        "overwrite": True,
    }
    cmd = command(["a.nc", "b.nc"], **options)
    assert cmd[0] == str(resolve_fake)
    assert cmd[1:] == build_args(["a.nc", "b.nc"], **options)


def test_command_resolves_through_the_module(resolve_fake, monkeypatch):
    # `from . import _binary` is what makes the fixture's patch take
    monkeypatch.chdir(os.fspath(resolve_fake.parent))
    assert command("a.nc")[0] == str(resolve_fake)


def test_command_reports_the_same_errors_as_build_args(resolve_fake):
    assert resolve_fake.exists()
    with pytest.raises(ValueError, match="exclude each other"):
        command("a.nc", savefig=True, record=True)
