"""Python values written in the app's keyword syntax."""

import datetime as dt
import math
from pathlib import Path

import numpy as np
import pytest

from cdfviewer._format import (
    Raw,
    Sym,
    format_dims,
    format_kwargs,
    format_save_options,
    format_value,
    raw,
    sym,
)

# ------------------------------------------------------------ sym / raw ----


def test_sym_is_a_str_subclass():
    value = sym("balance")
    assert isinstance(value, Sym)
    assert isinstance(value, str)
    assert value == "balance"


def test_raw_is_a_str_subclass():
    value = raw("Makie.Symlog10(1e-2)")
    assert isinstance(value, Raw)
    assert isinstance(value, str)
    assert value == "Makie.Symlog10(1e-2)"


def test_sym_and_raw_are_distinct_types():
    assert not isinstance(sym("x"), Raw)
    assert not isinstance(raw("x"), Sym)


# --------------------------------------------------------- format_value ----


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        # strings
        ("balance", '"balance"'),
        ("", '""'),
        ('say "hi"', r'"say \"hi\""'),
        (r"a\b", r'"a\\b"'),
        (r'both\"', r'"both\\\""'),
        ("with, comma", '"with, comma"'),
        # bool before int
        (True, "true"),
        (False, "false"),
        # nothing
        (None, "nothing"),
        # ints
        (0, "0"),
        (7, "7"),
        (-3, "-3"),
        (10**20, "100000000000000000000"),
        # floats
        (1.5, "1.5"),
        (0.1, "0.1"),
        (-2.0, "-2.0"),
        (1e-10, "1e-10"),
        (float("inf"), "Inf"),
        (float("-inf"), "-Inf"),
        (float("nan"), "NaN"),
        # symbols and verbatim text
        (Sym("balance"), ":balance"),
        (sym("lt"), ":lt"),
        (Raw("Makie.Symlog10(1e-2)"), "Makie.Symlog10(1e-2)"),
        (raw("1:10"), "1:10"),
        (raw('no "escaping" here'), 'no "escaping" here'),
        # tuples
        ((), "()"),
        ((5,), "(5,)"),
        ((1, 2), "(1, 2)"),
        ((1, (2, 3)), "(1, (2, 3))"),
        ((sym("red"), 0.6), "(:red, 0.6)"),
        # lists
        ([], "[]"),
        ([1, 2], "[1, 2]"),
        ([[1, 2], [3, 4]], "[[1, 2], [3, 4]]"),
        (["a", None, True], '["a", nothing, true]'),
        ([(1, 2)], "[(1, 2)]"),
    ],
)
def test_format_value(value, expected):
    assert format_value(value) == expected


def test_bool_wins_over_int():
    # a plain `isinstance(value, int)` first would write 1 and 0
    yes, one = True, 1
    assert format_value(yes) == "true"
    assert format_value(one) == "1"


def test_float_uses_repr_and_round_trips():
    for value in (0.1, 1 / 3, 1e300, 5e-324):
        assert float(format_value(value)) == value


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (
            dt.datetime(2026, 8, 22, 1, 2, 3),  # noqa: DTZ001
            'DateTime("2026-08-22T01:02:03.000")',
        ),
        (
            dt.datetime(2026, 8, 22, 1, 2, 3, 456789),  # noqa: DTZ001
            'DateTime("2026-08-22T01:02:03.456")',
        ),
        (
            dt.datetime(2026, 8, 22),  # noqa: DTZ001
            'DateTime("2026-08-22T00:00:00.000")',
        ),
        (dt.date(2026, 8, 22), 'Date("2026-08-22")'),
    ],
)
def test_format_value_dates(value, expected):
    assert format_value(value) == expected


def test_timezone_aware_datetime_is_refused():
    aware = dt.datetime(2026, 8, 22, tzinfo=dt.UTC)
    with pytest.raises(TypeError, match="timezone-aware"):
        format_value(aware)


@pytest.mark.parametrize(
    "value", [range(10), range(1, 10), range(1, 10, 2), slice(1, 10)]
)
def test_ranges_and_slices_are_refused(value):
    with pytest.raises(TypeError) as excinfo:
        format_value(value)
    message = str(excinfo.value)
    assert "raw(" in message
    assert "frames" in message


def test_path_is_written_as_a_string(tmp_path):
    assert format_value(tmp_path) == f'"{tmp_path}"'
    assert format_value(Path("rel/x.nc")) == '"rel/x.nc"'


def test_nested_path_is_written_as_a_string():
    assert format_value([Path("a.nc")]) == '["a.nc"]'


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (np.int64(7), "7"),
        (np.int32(-3), "-3"),
        (np.uint8(2), "2"),
        (np.float64(1.5), "1.5"),
        (np.float32(0.5), "0.5"),
        (np.True_, "true"),
        (np.False_, "false"),
        (np.str_("hi"), '"hi"'),
        (np.array([1, 2, 3]), "[1, 2, 3]"),
        (np.array([[1, 2], [3, 4]]), "[[1, 2], [3, 4]]"),
        (np.array([]), "[]"),
        (np.array(3.5), "3.5"),
        (np.ma.masked_array([1, 2]), "[1, 2]"),
        (np.datetime64("2026-08-22"), 'Date("2026-08-22")'),
        (
            np.datetime64("2026-08-22T01:02:03"),
            'DateTime("2026-08-22T01:02:03.000")',
        ),
    ],
)
def test_numpy_values(value, expected):
    assert format_value(value) == expected


def test_numpy_scalar_in_a_tuple():
    assert format_value((np.int64(1), np.float64(2.5))) == "(1, 2.5)"


def test_numpy_object_without_tolist_is_refused():
    # numpy.dtypes.Int64DType lives under "numpy." but is no value
    with pytest.raises(TypeError, match="cannot write a"):
        format_value(np.dtype("int64"))


class _Opaque:
    pass


@pytest.mark.parametrize(
    "value",
    [{1, 2}, frozenset(), _Opaque(), {"a": 1}, b"bytes", dt.time(1, 2), print],
)
def test_unsupported_types_are_refused(value):
    with pytest.raises(TypeError) as excinfo:
        format_value(value)
    assert "sym()" in str(excinfo.value)
    assert "raw()" in str(excinfo.value)


def test_the_refusal_names_the_type():
    with pytest.raises(TypeError, match="cannot write a set"):
        format_value({1})


def test_an_unsupported_value_inside_a_container_is_refused():
    with pytest.raises(TypeError, match="cannot write a set"):
        format_value([1, {2}])


# -------------------------------------------------------- format_kwargs ----


def test_format_kwargs_empty():
    assert format_kwargs({}) == ""


def test_format_kwargs_keeps_the_order_it_was_given():
    kwargs = {"zorder": 1, "alpha": 0.5, "colormap": "balance"}
    assert format_kwargs(kwargs) == 'zorder=1, alpha=0.5, colormap="balance"'
    reversed_kwargs = dict(reversed(list(kwargs.items())))
    assert format_kwargs(reversed_kwargs) == (
        'colormap="balance", alpha=0.5, zorder=1'
    )


def test_format_kwargs_formats_every_value():
    line = format_kwargs(
        {"levels": [1, 2], "pos": sym("lt"), "scale": raw("log10")}
    )
    assert line == "levels=[1, 2], pos=:lt, scale=log10"


def test_format_kwargs_refuses_a_bad_value():
    with pytest.raises(TypeError, match="cannot write a set"):
        format_kwargs({"colormap": {"balance"}})


# ---------------------------------------------------------- format_dims ----


def test_format_dims_empty():
    assert format_dims({}) == ""


def test_format_dims_pairs_are_comma_separated_without_spaces():
    assert format_dims({"z": 0, "time": 3}) == "z=0,time=3"


def test_format_dims_takes_numpy_integers():
    assert format_dims({"z": np.int64(0), "time": np.int32(3)}) == "z=0,time=3"


def test_format_dims_takes_negative_indices():
    assert format_dims({"time": -1}) == "time=-1"


@pytest.mark.parametrize("index", [True, False, 1.0, "3", None, (1,)])
def test_format_dims_refuses_non_integers(index):
    with pytest.raises(TypeError, match=r"dims\['z'\] must be an int"):
        format_dims({"z": index})


def test_format_dims_names_the_offending_type():
    with pytest.raises(TypeError, match="got bool"):
        format_dims({"z": True})


# -------------------------------------------------- format_save_options ----


def test_format_save_options_nothing_set():
    assert format_save_options() == ""


@pytest.mark.parametrize(
    ("option", "expected"),
    [
        ({"filename": "out.png"}, 'filename="out.png"'),
        ({"framerate": 24}, "framerate=24"),
        ({"px_per_unit": 2}, "px_per_unit=2"),
        ({"frames": (1, 10)}, "range=1:10"),
        ({"frames": (1, 2, 10)}, "range=1:2:10"),
        ({"overwrite": True}, "overwrite=true"),
        ({"overwrite": False}, "overwrite=false"),
    ],
)
def test_format_save_options_one_at_a_time(option, expected):
    assert format_save_options(**option) == expected


def test_format_save_options_in_the_documented_order():
    assert format_save_options(
        overwrite=False,
        frames=(1, 2, 10),
        px_per_unit=2,
        framerate=24,
        filename="movie.mp4",
    ) == (
        'filename="movie.mp4", framerate=24, px_per_unit=2, '
        "range=1:2:10, overwrite=false"
    )


def test_format_save_options_takes_a_path(tmp_path):
    target = tmp_path / "fig.png"
    assert format_save_options(filename=target) == f'filename="{target}"'


def test_format_save_options_quotes_a_filename_with_spaces():
    assert format_save_options(filename="my fig.png") == (
        'filename="my fig.png"'
    )


def test_format_save_options_takes_numpy_integers():
    assert format_save_options(
        framerate=np.int64(24), px_per_unit=np.int64(2)
    ) == ("framerate=24, px_per_unit=2")


def test_format_save_options_takes_a_list_of_frames():
    assert format_save_options(frames=[1, 10]) == "range=1:10"


def test_format_save_options_takes_a_numpy_array_of_frames():
    assert format_save_options(frames=np.array([1, 10])) == "range=1:10"


@pytest.mark.parametrize("frames", [(1,), (1, 2, 3, 4), ()])
def test_format_save_options_refuses_the_wrong_number_of_frames(frames):
    with pytest.raises(TypeError, match="frames must be"):
        format_save_options(frames=frames)


@pytest.mark.parametrize(
    "frames", [("a", "b"), (1.0, 2), (True, 2), (1, None)]
)
def test_format_save_options_refuses_non_integer_frames(frames):
    with pytest.raises(TypeError, match="frames must be an int"):
        format_save_options(frames=frames)


def test_format_save_options_refuses_a_string_of_frames():
    with pytest.raises(TypeError, match="frames must be"):
        format_save_options(frames="1:10")


@pytest.mark.parametrize("frames", [range(1, 10), slice(1, 10)])
def test_format_save_options_refuses_a_range_of_frames(frames):
    # range(1, 10) as (start, stop) would silently drop the last frame
    with pytest.raises(TypeError) as excinfo:
        format_save_options(frames=frames)
    assert "raw(" in str(excinfo.value)


@pytest.mark.parametrize("value", [1.5, "24", True])
def test_format_save_options_refuses_a_bad_framerate(value):
    with pytest.raises(TypeError, match="framerate must be an int"):
        format_save_options(framerate=value)


@pytest.mark.parametrize("value", [1.5, "2", False])
def test_format_save_options_refuses_a_bad_px_per_unit(value):
    with pytest.raises(TypeError, match="px_per_unit must be an int"):
        format_save_options(px_per_unit=value)


def test_format_save_options_zero_is_not_treated_as_unset():
    assert format_save_options(framerate=0, px_per_unit=0) == (
        "framerate=0, px_per_unit=0"
    )


def test_nan_and_inf_survive_a_round_trip_through_kwargs():
    line = format_kwargs({"a": math.inf, "b": -math.inf, "c": math.nan})
    assert line == "a=Inf, b=-Inf, c=NaN"
