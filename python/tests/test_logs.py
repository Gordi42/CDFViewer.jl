"""The app's log output, read back into records."""

from pathlib import Path

import pytest

from cdfviewer._errors import CDFViewerError, CDFViewerWarning
from cdfviewer._logs import (
    Record,
    parse_records,
    raise_for_records,
    saved_path,
    strip_progress,
)

# what the spike saw while a recording ran (workplan.md, "Spike results")
PROGRESS = (
    "\rRecording   0%|          |  ETA: N/A\x1b[K"
    "\rRecording  67%|██████    |  ETA: 0:00:00\x1b[K"
    "\rRecording 100%|██████████| Time: 0:00:01\x1b[K\n"
    "[ Info: Saved animation to /data/out.mp4\n"
)
LOCATION = "└ @ CDFViewer.Plotting /x/CDFViewer.jl/src/Plotting.jl:123"


def test_strip_progress_drops_ansi_sequences():
    assert strip_progress("\x1b[32mgreen\x1b[0m") == "green"


def test_strip_progress_keeps_the_last_segment_of_a_line():
    assert strip_progress("first\rsecond\rthird") == "third"


def test_strip_progress_works_line_by_line():
    assert strip_progress("a\rb\nc\rd") == "b\nd"


def test_strip_progress_leaves_plain_text_alone():
    assert strip_progress("[ Info: hello\n") == "[ Info: hello\n"


def test_strip_progress_on_a_recording():
    assert strip_progress(PROGRESS) == (
        "Recording 100%|██████████| Time: 0:00:01\n"
        "[ Info: Saved animation to /data/out.mp4\n"
    )


def test_parse_records_of_a_single_line():
    assert parse_records("[ Info: hello") == [Record("Info", "hello")]


def test_parse_records_of_a_block():
    text = "┌ Info: Current plot settings:\n│ a => 1\n└ b => 2"
    assert parse_records(text) == [
        Record("Info", "Current plot settings:\na => 1\nb => 2")
    ]


@pytest.mark.parametrize("level", ["Warning", "Error", "Debug"])
def test_parse_records_of_a_located_block(level):
    text = f"┌ {level}: something happened\n{LOCATION}"
    assert parse_records(text) == [Record(level, "something happened")]


def test_parse_records_keeps_the_order_of_mixed_shapes():
    lines = [
        "[ Info: first",
        "┌ Warning: reverting: xunit",
        LOCATION,
        "┌ Error: xunit must be one of (mm, cm)",
        LOCATION,
        "[ Info: last",
    ]
    text = "\n".join(lines)
    assert [(r.level, r.message) for r in parse_records(text)] == [
        ("Info", "first"),
        ("Warning", "reverting: xunit"),
        ("Error", "xunit must be one of (mm, cm)"),
        ("Info", "last"),
    ]


def test_parse_records_closes_a_block_that_never_ended():
    text = "┌ Info: open\n│ more\nunrelated\n[ Info: next"
    assert parse_records(text) == [
        Record("Info", "open\nmore"),
        Record("Info", "next"),
    ]


def test_parse_records_closes_a_block_at_the_end_of_the_text():
    assert parse_records("┌ Warning: open") == [Record("Warning", "open")]


def test_parse_records_starts_a_block_right_after_an_unclosed_one():
    text = "┌ Warning: one\n┌ Error: two\n" + LOCATION
    assert parse_records(text) == [
        Record("Warning", "one"),
        Record("Error", "two"),
    ]


def test_parse_records_skips_everything_else():
    text = "CDFViewer> \nType 'help' for a list of commands.\n└ stray\n"
    assert parse_records(text) == []


def test_parse_records_of_empty_text():
    assert parse_records("") == []


def test_parse_records_strips_the_progress_bar_first():
    assert parse_records(PROGRESS) == [
        Record("Info", "Saved animation to /data/out.mp4")
    ]


def test_saved_path_of_a_figure():
    records = [Record("Info", "Saved figure to /data/a.png")]
    assert saved_path(records) == Path("/data/a.png")


def test_saved_path_of_an_animation(tmp_path):
    target = tmp_path / "movie.mp4"
    records = [Record("Info", f"Saved animation to {target}")]
    assert saved_path(records) == target


def test_saved_path_takes_the_last_one(tmp_path):
    records = [
        Record("Info", f"Saved figure to {tmp_path / 'one.png'}"),
        Record("Info", "unrelated"),
        Record("Info", f"Saved figure to {tmp_path / 'two.png'}"),
    ]
    assert saved_path(records) == tmp_path / "two.png"


def test_saved_path_ignores_a_warning_that_looks_like_one(tmp_path):
    records = [Record("Warning", f"Saved figure to {tmp_path / 'a.png'}")]
    assert saved_path(records) is None


def test_saved_path_without_a_save():
    assert saved_path([Record("Info", "Ready.")]) is None


def test_raise_for_records_is_quiet_without_records():
    raise_for_records([])


def test_raise_for_records_warns_once_per_warning():
    records = [
        Record("Warning", "first"),
        Record("Info", "not a warning"),
        Record("Warning", "second"),
    ]
    with pytest.warns(CDFViewerWarning) as caught:
        raise_for_records(records)
    assert [str(w.message) for w in caught] == ["first", "second"]


def test_raise_for_records_raises_on_an_error():
    records = [Record("Error", "xunit must be one of (mm, cm)")]
    argv = ["cdfviewer", "data.nc", "--savefig"]
    with pytest.raises(CDFViewerError) as excinfo:
        raise_for_records(records, argv=argv, output="[ Info: hi\n")
    error = excinfo.value
    assert "xunit must be one of" in str(error)
    assert error.argv == argv
    assert error.output == "[ Info: hi\n"
    assert error.returncode is None


def test_raise_for_records_reports_several_errors():
    records = [Record("Error", "one"), Record("Error", "two")]
    with pytest.raises(CDFViewerError, match=r"2 errors: one \| two"):
        raise_for_records(records)


def test_raise_for_records_warns_before_it_raises():
    records = [Record("Warning", "reverting: xunit"), Record("Error", "bad")]
    with (
        pytest.warns(CDFViewerWarning, match="reverting"),
        pytest.raises(CDFViewerError, match="bad"),
    ):
        raise_for_records(records)
