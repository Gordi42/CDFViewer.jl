"""
In-memory datasets, written to a temporary file the app can open.

Work package C (stubs). xarray is imported lazily; it is an optional
dependency (``pip install cdfviewer[xarray]``).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from pathlib import Path

    import xarray as xr

COMPLEX_MODES = ("split", "abs", "real", "imag", "phase")


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

    def __init__(self, path: Path, var: str | None = None) -> None:
        self.path = path
        self.var = var

    def cleanup(self) -> None:
        """Delete the file; safe to call twice."""
        raise NotImplementedError


def is_in_memory(obj: object) -> bool:
    """Whether ``obj`` is a Dataset, a DataArray or a numpy array."""
    raise NotImplementedError


def prepare(
    dataset: xr.Dataset, *, complex_as: str
) -> tuple[xr.Dataset, dict[str, str]]:
    """
    The dataset as the app can read it, and the renames that took.

    Complex variables are split into ``<name>_real``/``<name>_imag`` or
    reduced per ``complex_as``; ``float16`` becomes ``float32``; object
    dtypes are an error.
    """
    raise NotImplementedError


def write_temp(
    obj: Any, *, complex_as: str = "split", var: str | None = None
) -> TempDataset:
    """Write ``obj`` under the temp directory and hand back its path."""
    raise NotImplementedError
