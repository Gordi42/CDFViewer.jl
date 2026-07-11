"""Generate the zarr **v3** test fixture ``test/data/zarr/2d_scalar_v3.zarr``.

Deliberately separate from ``generate_zarr_fixtures.py``: that script drives
the fridom framework2 tensorstore Writer, which can only emit zarr v2. This
script needs no fridom at all — only ``zarr>=3``, ``xarray``, ``numpy`` and
``pandas`` — and writes the store through plain xarray with
``zarr_format=3``. Regenerate with a single ephemeral-deps command:

    cd test/data && uv run --with "zarr>=3" --with xarray \
        --with numpy --with pandas python generate_zarr_v3_fixture.py

The store mirrors ``2d_scalar.zarr`` in spirit but smaller: one variable
``temp(time, x, y)`` of shape (3, 8, 8), float64, fully deterministic
analytic values

    temp[it, ix, iy] = cos(it * 0.5) * sin(2*pi*x[ix]) * cos(2*pi*y[iy])

with cell-center coords x, y in [0, 1) and a datetime64 time axis (30-minute
steps from 2020-01-01) so xarray applies CF time encoding. Ground-truth
values are printed on generation and recorded in ``zarr/MANIFEST.md``.
"""

import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr
import zarr

STORE = Path(__file__).parent / "zarr" / "2d_scalar_v3.zarr"

NT, NX, NY = 3, 8, 8


def build_dataset() -> xr.Dataset:
    x = (np.arange(NX) + 0.5) / NX  # cell centers of [0, 1)
    y = (np.arange(NY) + 0.5) / NY
    it = np.arange(NT)
    time = pd.date_range("2020-01-01", periods=NT, freq="30min")

    data = (
        np.cos(it * 0.5)[:, None, None]
        * np.sin(2 * np.pi * x)[None, :, None]
        * np.cos(2 * np.pi * y)[None, None, :]
    )

    return xr.Dataset(
        {
            "temp": (
                ("time", "x", "y"),
                data,
                {"units": "K", "long_name": "Temperature"},
            )
        },
        coords={
            "time": ("time", time, {"long_name": "time"}),
            "x": ("x", x, {"units": "1", "long_name": "x coordinate"}),
            "y": ("y", y, {"units": "1", "long_name": "y coordinate"}),
        },
        attrs={
            "Conventions": "CF-1.10",
            "title": "zarr v3 fixture: 2D scalar",
        },
    )


def main() -> None:
    assert zarr.__version__.split(".")[0] >= "3", "needs zarr>=3"
    ds = build_dataset()
    if STORE.exists():
        shutil.rmtree(STORE)
    ds.to_zarr(STORE, zarr_format=3, consolidated=False)

    # Ground truth for the manifest / Julia tests (0-based, time-first)
    for idx in [(0, 0, 0), (1, 4, 4), (2, 7, 7)]:
        print(f"temp[{', '.join(map(str, idx))}] = {ds.temp.values[idx]!r}")
    print("time:", list(ds.time.values))

    # Sanity: genuinely v3 — zarr.json everywhere, no v2 metadata files
    names = {p.name for p in STORE.rglob("*") if p.is_file()}
    assert "zarr.json" in names
    assert not names & {".zgroup", ".zarray", ".zattrs", ".zmetadata"}
    print("store:", STORE)


if __name__ == "__main__":
    main()
