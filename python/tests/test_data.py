"""In-memory datasets, written to a temporary file the app can open."""

import sys
from pathlib import Path

import pytest

from cdfviewer import _config, _data
from cdfviewer._errors import CDFViewerError, CDFViewerWarning

xr = pytest.importorskip("xarray")
np = pytest.importorskip("numpy")

# Warnings of the writers themselves, not of anything this package does:
# the locked netCDF4 wheel is built against an older numpy, and zarr says
# that the consolidated metadata xarray writes is not in the v3 spec.
pytestmark = [
    pytest.mark.filterwarnings(
        "ignore:numpy.ndarray size changed:RuntimeWarning"
    ),
    pytest.mark.filterwarnings(
        "ignore:Setting the shape on a NumPy array:DeprecationWarning"
    ),
    pytest.mark.filterwarnings("ignore:Consolidated metadata is currently"),
]


@pytest.fixture(autouse=True)
def _tmpdir(tmp_path, monkeypatch):
    """Keep every temporary dataset inside the test's own directory."""
    monkeypatch.setenv(_config.ENV_TMPDIR, str(tmp_path / "scratch"))


@pytest.fixture
def dataset():
    """A small dataset with one coordinate and attributes."""
    data = np.arange(6.0).reshape(2, 3)
    return xr.Dataset(
        {"temp": (("time", "x"), data, {"units": "K", "long_name": "Temp"})},
        coords={"time": [0, 1], "x": [0.0, 1.0, 2.0]},
        attrs={"title": "small"},
    )


@pytest.fixture
def complex_dataset():
    """A dataset holding one complex variable."""
    values = np.array([[1 + 1j, 0 - 2j]])
    return xr.Dataset(
        {"psi": (("t", "x"), values, {"units": "1", "long_name": "Psi"})}
    )


# ------------------------------------------------------------- is_in_memory


@pytest.mark.parametrize(
    "obj",
    ["data.nc", Path("data.nc"), ["a.nc", "b.nc"], ("a.nc",), None, 3],
)
def test_is_in_memory_says_no_to_paths(obj):
    assert _data.is_in_memory(obj) is False


def test_is_in_memory_of_a_dataset(dataset):
    assert _data.is_in_memory(dataset) is True


def test_is_in_memory_of_a_data_array(dataset):
    assert _data.is_in_memory(dataset["temp"]) is True


def test_is_in_memory_of_a_numpy_array():
    assert _data.is_in_memory(np.zeros(3)) is True


def test_is_in_memory_duck_types_a_writer():
    class Writable:
        def to_netcdf(self, path):
            """Pretend to be a Dataset from somewhere else."""

    assert _data.is_in_memory(Writable()) is True


def test_is_in_memory_without_numpy(monkeypatch):
    monkeypatch.delitem(sys.modules, "numpy", raising=False)
    assert _data.is_in_memory(object()) is False


# ------------------------------------------------------------------ prepare


def test_prepare_leaves_a_plain_dataset_alone(dataset):
    prepared, renames = _data.prepare(dataset, complex_as="split")
    assert renames == {}
    assert prepared.identical(dataset)


def test_prepare_rejects_an_unknown_mode(dataset):
    with pytest.raises(ValueError, match="complex_as must be one of"):
        _data.prepare(dataset, complex_as="magnitude")


def test_prepare_splits_a_complex_variable(complex_dataset):
    prepared, renames = _data.prepare(complex_dataset, complex_as="split")
    assert renames == {"psi": "psi_real"}
    assert "psi" not in prepared
    assert prepared["psi_real"].values.tolist() == [[1.0, 0.0]]
    assert prepared["psi_imag"].values.tolist() == [[1.0, -2.0]]
    assert prepared["psi_real"].dims == ("t", "x")


def test_prepare_copies_the_attributes_of_a_split(complex_dataset):
    prepared, _ = _data.prepare(complex_dataset, complex_as="split")
    assert prepared["psi_real"].attrs == {
        "units": "1",
        "long_name": "Psi (real part)",
    }
    assert prepared["psi_imag"].attrs == {
        "units": "1",
        "long_name": "Psi (imaginary part)",
    }


def test_prepare_splits_without_a_long_name():
    data = xr.Dataset({"psi": ("x", np.array([1 + 1j]), {"units": "1"})})
    prepared, _ = _data.prepare(data, complex_as="split")
    assert prepared["psi_real"].attrs == {"units": "1"}


@pytest.mark.parametrize(
    ("mode", "expected"),
    [
        ("abs", [[2.0**0.5, 2.0]]),
        ("real", [[1.0, 0.0]]),
        ("imag", [[1.0, -2.0]]),
        ("phase", [[np.pi / 4, -np.pi / 2]]),
    ],
)
def test_prepare_reduces_a_complex_variable(complex_dataset, mode, expected):
    prepared, renames = _data.prepare(complex_dataset, complex_as=mode)
    assert renames == {"psi": "psi"}
    assert list(prepared.data_vars) == ["psi"]
    assert prepared["psi"].values == pytest.approx(np.array(expected))
    assert prepared["psi"].attrs == {"units": "1", "long_name": "Psi"}


def test_prepare_widens_float16():
    data = xr.Dataset(
        {"t": ("x", np.array([1.0, 2.0], dtype="float16"), {"units": "K"})}
    )
    prepared, renames = _data.prepare(data, complex_as="split")
    assert prepared["t"].dtype == np.dtype("float32")
    assert prepared["t"].attrs == {"units": "K"}
    assert renames == {}


def test_prepare_refuses_object_dtype():
    data = xr.Dataset({"t": ("x", np.array([{"a": 1}, None], dtype=object))})
    with pytest.raises(CDFViewerError, match="'t' has dtype object"):
        _data.prepare(data, complex_as="split")


def test_prepare_leaves_the_input_untouched(complex_dataset):
    _data.prepare(complex_dataset, complex_as="abs")
    assert complex_dataset["psi"].dtype.kind == "c"


def test_prepare_keeps_coordinates_and_attributes(dataset):
    dataset["psi"] = (("time", "x"), np.zeros((2, 3), dtype=complex))
    prepared, _ = _data.prepare(dataset, complex_as="split")
    assert prepared.attrs == {"title": "small"}
    assert list(prepared.coords) == ["time", "x"]
    assert prepared["temp"].attrs["long_name"] == "Temp"


# --------------------------------------------------------------- write_temp


def test_write_temp_of_a_dataset(dataset, tmp_path):
    temp = _data.write_temp(dataset)
    assert temp.var is None
    assert temp.path.name == "dataset.nc"
    assert temp.path.is_relative_to(tmp_path)
    with xr.open_dataset(temp.path) as written:
        assert written["temp"].values.tolist() == [[0, 1, 2], [3, 4, 5]]
        assert written["temp"].attrs["units"] == "K"
    temp.cleanup()


def test_write_temp_of_a_named_data_array(dataset):
    temp = _data.write_temp(dataset["temp"])
    assert temp.var == "temp"
    with xr.open_dataset(temp.path) as written:
        assert list(written.data_vars) == ["temp"]
    temp.cleanup()


def test_write_temp_of_an_unnamed_data_array():
    array = xr.DataArray(np.zeros((2, 2)))
    temp = _data.write_temp(array)
    assert temp.var == "data"
    temp.cleanup()


def test_write_temp_of_a_numpy_array():
    temp = _data.write_temp(np.zeros((2, 3, 4)))
    assert temp.var == "data"
    with xr.open_dataset(temp.path) as written:
        assert written["data"].dims == ("dim_0", "dim_1", "dim_2")
    temp.cleanup()


def test_write_temp_keeps_an_explicit_var(dataset):
    temp = _data.write_temp(dataset, var="temp")
    assert temp.var == "temp"
    temp.cleanup()


def test_write_temp_resolves_a_complex_var(complex_dataset):
    with pytest.warns(CDFViewerWarning, match="'psi' is complex"):
        temp = _data.write_temp(complex_dataset, var="psi")
    assert temp.var == "psi_real"
    temp.cleanup()


def test_write_temp_resolves_a_complex_data_array(complex_dataset):
    with pytest.warns(CDFViewerWarning, match="'psi' is complex"):
        temp = _data.write_temp(complex_dataset["psi"])
    assert temp.var == "psi_real"
    temp.cleanup()


def test_write_temp_resolves_a_vector_pair():
    data = xr.Dataset(
        {
            "u": ("x", np.array([1 + 1j])),
            "v": ("x", np.array([2.0])),
        }
    )
    with pytest.warns(CDFViewerWarning, match="'u' is complex"):
        temp = _data.write_temp(data, var="u,v")
    assert temp.var == "u_real,v"
    temp.cleanup()


def test_write_temp_does_not_warn_when_reducing(complex_dataset):
    temp = _data.write_temp(complex_dataset, var="psi", complex_as="abs")
    assert temp.var == "psi"
    temp.cleanup()


def test_write_temp_creates_a_missing_temp_directory(dataset, tmp_path):
    assert not (tmp_path / "scratch").exists()
    temp = _data.write_temp(dataset)
    assert temp.path.exists()
    temp.cleanup()


def test_write_temp_needs_xarray(monkeypatch, dataset):
    monkeypatch.setitem(sys.modules, "xarray", None)
    with pytest.raises(CDFViewerError, match="pip install cdfviewer"):
        _data.write_temp(dataset)


def test_write_temp_cleans_up_after_a_failed_write(monkeypatch, dataset):
    monkeypatch.setattr(_data, "_importable", lambda name: False)  # noqa: ARG005
    with pytest.raises(CDFViewerError, match="netCDF4, h5netcdf or zarr"):
        _data.write_temp(dataset)
    assert list(_config.tmpdir().iterdir()) == []


# ------------------------------------------------------------ writer choice


class _Recorder:

    """A stand-in dataset that only remembers how it was written."""

    def __init__(self):
        self.calls = []

    def to_netcdf(self, path, engine):
        self.calls.append(("netcdf", path, engine))

    def to_zarr(self, path):
        self.calls.append(("zarr", path))


@pytest.mark.parametrize(
    ("available", "expected"),
    [
        ({"netCDF4", "h5netcdf", "zarr"}, ("netcdf", "dataset.nc", "netcdf4")),
        ({"h5netcdf", "zarr"}, ("netcdf", "dataset.nc", "h5netcdf")),
        ({"zarr"}, ("zarr", "dataset.zarr", None)),
    ],
)
def test_write_picks_the_first_writer_there_is(
    monkeypatch, tmp_path, available, expected
):
    monkeypatch.setattr(_data, "_importable", lambda name: name in available)
    recorder = _Recorder()
    path = _data._write(recorder, tmp_path)
    kind, name, engine = expected
    assert path == tmp_path / name
    assert recorder.calls[0][0] == kind
    assert recorder.calls[0][1] == path
    if engine is not None:
        assert recorder.calls[0][2] == engine


def test_write_without_a_writer(monkeypatch, tmp_path):
    monkeypatch.setattr(_data, "_importable", lambda name: False)  # noqa: ARG005
    with pytest.raises(CDFViewerError, match="netCDF4, h5netcdf or zarr"):
        _data._write(_Recorder(), tmp_path)


def test_importable_answers_for_real_modules():
    assert _data._importable("json") is True
    assert _data._importable("not_a_module_at_all") is False


def test_write_temp_through_zarr(monkeypatch, dataset):
    monkeypatch.setattr(_data, "_importable", lambda name: name == "zarr")
    temp = _data.write_temp(dataset)
    assert temp.path.name == "dataset.zarr"
    with xr.open_zarr(temp.path) as written:
        assert written["temp"].shape == (2, 3)
    temp.cleanup()


# -------------------------------------------------------------- TempDataset


def test_cleanup_removes_the_whole_directory(dataset):
    temp = _data.write_temp(dataset)
    directory = temp.path.parent
    temp.cleanup()
    assert not directory.exists()
    temp.cleanup()  # idempotent


def test_temp_dataset_defaults_to_the_file_s_directory(tmp_path):
    temp = _data.TempDataset(tmp_path / "sub" / "dataset.nc")
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "dataset.nc").write_bytes(b"x")
    assert temp.var is None
    temp.cleanup()
    assert not (tmp_path / "sub").exists()
