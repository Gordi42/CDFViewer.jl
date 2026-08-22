"""
In-memory datasets, written to a temporary file the app can open.

An xarray ``Dataset``, an xarray ``DataArray`` or a numpy array is put
through a "make it viewable" pass (`prepare`) and written under
`cdfviewer._config.tmpdir`, because the app reads files. xarray is
imported lazily; it is an optional dependency (``pip install
cdfviewer[xarray]``).
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile
import warnings
from pathlib import Path
from typing import TYPE_CHECKING, Any

from . import _config
from ._errors import CDFViewerError, CDFViewerWarning

if TYPE_CHECKING:  # pragma: no cover
    import xarray as xr

COMPLEX_MODES = ("split", "abs", "real", "imag", "phase")
_NETCDF_ENGINES = (("netCDF4", "netcdf4"), ("h5netcdf", "h5netcdf"))
_XARRAY_HINT = (
    "in-memory data is written through xarray, which is not installed: "
    "pip install cdfviewer[xarray]"
)
_WRITER_HINT = (
    "writing an in-memory dataset needs one of netCDF4, h5netcdf or "
    "zarr: pip install cdfviewer[xarray]"
)


class TempDataset:

    """
    A dataset written to a temporary file, deleted on `cleanup`.

    Attributes
    ----------
    path : Path
        The file (or zarr store) the app opens.
    var : str | None
        The variable to select by default, when the input implied one.
    """

    def __init__(
        self,
        path: Path,
        var: str | None = None,
        *,
        directory: Path | None = None,
    ) -> None:
        self.path = path
        self.var = var
        self._directory = path.parent if directory is None else directory

    def cleanup(self) -> None:
        """Delete the file; safe to call twice."""
        shutil.rmtree(self._directory, ignore_errors=True)


def is_in_memory(obj: object) -> bool:
    """Whether ``obj`` is a Dataset, a DataArray or a numpy array."""
    if isinstance(obj, str | os.PathLike):
        return False
    if type(obj).__module__.split(".")[0] == "xarray":
        return True
    if hasattr(obj, "to_netcdf"):
        return True
    numpy = sys.modules.get("numpy")
    return numpy is not None and isinstance(obj, numpy.ndarray)


def prepare(
    dataset: xr.Dataset, *, complex_as: str
) -> tuple[xr.Dataset, dict[str, str]]:
    """
    The dataset as the app can read it, and the renames that took.

    Complex variables are split into ``<name>_real``/``<name>_imag`` or
    reduced per ``complex_as``; ``float16`` becomes ``float32``; object
    dtypes are an error. Coordinates and attributes are left alone.

    Parameters
    ----------
    dataset : xarray.Dataset
        The dataset to write.
    complex_as : str
        One of `COMPLEX_MODES`: how complex variables are made real.

    Returns
    -------
    tuple[xarray.Dataset, dict[str, str]]
        The converted dataset, and for every complex variable the name
        that now holds it (``<name>_real`` when it was split).

    Raises
    ------
    ValueError
        For a ``complex_as`` that is not one of `COMPLEX_MODES`.
    CDFViewerError
        For a variable of object dtype, which has no file format.
    """
    if complex_as not in COMPLEX_MODES:
        msg = (
            f"complex_as must be one of {', '.join(COMPLEX_MODES)}, "
            f"got {complex_as!r}"
        )
        raise ValueError(msg)
    import numpy as np  # noqa: PLC0415  (numpy comes with xarray, lazily)

    out = dataset.copy()
    renames: dict[str, str] = {}
    for name, array in dataset.data_vars.items():
        if array.dtype.kind == "c":
            renames[str(name)] = _make_real(out, str(name), array, complex_as)
        elif array.dtype.kind == "O":
            msg = (
                f"variable {name!r} has dtype object, which cannot be "
                "written; convert it to a number or a fixed-width string"
            )
            raise CDFViewerError(msg)
        elif array.dtype == np.float16:
            out[name] = _like(array, array.data.astype("float32"))
    return out, renames


def _make_real(
    out: xr.Dataset, name: str, array: xr.DataArray, complex_as: str
) -> str:
    """Replace the complex ``name`` in ``out``; the name it ends under."""
    import numpy as np  # noqa: PLC0415  (numpy comes with xarray, lazily)

    if complex_as == "split":
        real, imag = f"{name}_real", f"{name}_imag"
        del out[name]
        out[real] = _like(array, array.data.real, " (real part)")
        out[imag] = _like(array, array.data.imag, " (imaginary part)")
        return real
    reduce = {
        "abs": np.abs,
        "real": np.real,
        "imag": np.imag,
        "phase": np.angle,
    }[complex_as]
    out[name] = _like(array, reduce(array.data))
    return name


def _like(
    array: xr.DataArray, data: Any, suffix: str = ""
) -> xr.DataArray:
    """``array`` with other ``data``, its attributes carried over."""
    new = array.copy(data=data)
    attrs = dict(array.attrs)
    if suffix and "long_name" in attrs:
        attrs["long_name"] = f"{attrs['long_name']}{suffix}"
    new.attrs = attrs
    return new


def write_temp(
    obj: Any, *, complex_as: str = "split", var: str | None = None
) -> TempDataset:
    """
    Write ``obj`` under the temp directory and hand back its path.

    Parameters
    ----------
    obj : xarray.Dataset | xarray.DataArray | numpy.ndarray
        The data to write. A bare array is wrapped in a ``DataArray``
        named ``data`` with dimensions ``dim_0, dim_1, ...``.
    complex_as : str, optional
        How complex variables are made real (default: ``"split"``, see
        `prepare`).
    var : str | None, optional
        The variable the caller asked for, resolved through the renames
        of `prepare` (default: None).

    Returns
    -------
    TempDataset
        The written file and the variable to select by default; its
        `TempDataset.cleanup` removes the file again.

    Raises
    ------
    CDFViewerError
        When xarray is missing, and when no writer is installed.
    """
    xarray = _import_xarray()
    dataset, name = _as_dataset(xarray, obj)
    dataset, renames = prepare(dataset, complex_as=complex_as)
    name = _resolve_var(var if var is not None else name, renames)
    root = _config.tmpdir()
    root.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="cdfviewer-", dir=root))
    try:
        path = _write(dataset, directory)
    except BaseException:
        shutil.rmtree(directory, ignore_errors=True)
        raise
    return TempDataset(path, name, directory=directory)


def _import_xarray() -> Any:
    """The xarray module, or a `CDFViewerError` telling how to get it."""
    try:
        import xarray  # noqa: PLC0415  (optional dependency, lazy)
    except ImportError as error:
        raise CDFViewerError(_XARRAY_HINT) from error
    return xarray


def _as_dataset(xarray: Any, obj: Any) -> tuple[xr.Dataset, str | None]:
    """``obj`` as a Dataset, and the variable it implies, if any."""
    if isinstance(obj, xarray.Dataset):
        return obj, None
    if not isinstance(obj, xarray.DataArray):
        obj = xarray.DataArray(obj, name="data")
    name = str(obj.name) if obj.name is not None else "data"
    return obj.to_dataset(name=name), name


def _resolve_var(name: str | None, renames: dict[str, str]) -> str | None:
    """``name`` after `prepare`'s renames, warning where one applied."""
    if name is None:
        return None
    parts = [part.strip() for part in name.split(",")]
    resolved = [renames.get(part, part) for part in parts]
    for part, new in zip(parts, resolved, strict=True):
        if new != part:
            warnings.warn(
                f"{part!r} is complex and was split; plotting {new!r} "
                "instead (see complex_as)",
                CDFViewerWarning,
                stacklevel=4,
            )
    return ",".join(resolved)


def _importable(name: str) -> bool:
    """Whether ``name`` can be imported, without importing it."""
    return importlib.util.find_spec(name) is not None


def _write(dataset: xr.Dataset, directory: Path) -> Path:
    """Write ``dataset`` into ``directory`` with whatever writer there is."""
    for module, engine in _NETCDF_ENGINES:
        if _importable(module):
            path = directory / "dataset.nc"
            dataset.to_netcdf(path, engine=engine)
            return path
    if _importable("zarr"):
        path = directory / "dataset.zarr"
        dataset.to_zarr(path)
        return path
    raise CDFViewerError(_WRITER_HINT)
