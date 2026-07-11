"""Generate the zarr test fixtures under test/data/zarr/.

The fixtures are produced by the *real* fridom framework2 zarr Writer
(``fridom.framework2.io.writer.Writer``, a tensorstore-backed zarr-v2
sink) so that CDFViewer.jl is tested against real-world stores, not
hand-rolled ones.

Requirements
------------
A checkout of the fridom repository (branch with framework2), e.g. at
``~/Projects/fridom-dev``, managed with uv. Run from anywhere:

    uv run --project ~/Projects/fridom-dev python \
        test/data/generate_zarr_fixtures.py

The script is deterministic (fixed analytic fields, no RNG) and
regenerates every store from scratch (Writer mode="w" clobbers).
Output goes to the ``zarr/`` directory next to this file. After
generating, it prints a verification summary (dims, coords, ranges,
attrs, compressor, sample values) for each store.
"""
from pathlib import Path

import jax.numpy as jnp
import numpy as np

from fridom.framework2.grid.fields.metadata import FieldMetadata
from fridom.framework2.grid.fields.vector_field import VectorField
from fridom.framework2.grid.grid import Grid
from fridom.framework2.grid.meshes.interval import IntervalMesh
from fridom.framework2.io.triggers import every
from fridom.framework2.io.writer import Writer
from fridom.framework2.model.clock import Clock

OUT = Path(__file__).resolve().parent / "zarr"

DT = 0.5  # model-time step between written slices (seconds)


# ================================================================
#  Minimal duck-typed model (state + clock + field table)
# ================================================================
class Carry:
    """A minimal model_state: state + clock."""

    def __init__(self, state, clock):
        self.state = state
        self.clock = clock


class Table:
    """A minimal field table (all fields prognostic)."""

    def __init__(self, names):
        self.prognostic = tuple(names)
        self.diagnostic = ()
        self.auxiliary = ()
        self.names = self.prognostic


class Model:
    """The smallest thing Writer.bind consumes."""

    def __init__(self, state, clock):
        self.carry = Carry(state, clock)
        self.field_table = Table(tuple(state.component_names))


def clock_at(it, *, start_date=None):
    """Return a clock ticked to iteration ``it`` (time = it * DT)."""
    clock = Clock(start_date=start_date)
    for _ in range(it):
        clock = clock.tick(DT)
    return clock


def run_writer(path, base_state, iterations, *, start_date=None,
               mode="w", chunks=None, attrs=None):
    """Drive a Writer over ``iterations``, scaling fields by cos(t).

    Every written slice ``it`` holds ``cos(it * DT) * field0`` for
    each component — a deterministic 'evolution' whose ground truth
    is trivially reproducible.
    """
    fields = tuple(base_state.component_names)
    writer = Writer(path, fields=fields, trigger=every(steps=1),
                    mode=mode, chunks=chunks, attrs=attrs)
    writer.bind(Model(base_state, clock_at(iterations[0],
                                           start_date=start_date)))
    for it in iterations:
        t = it * DT
        factor = float(np.cos(t))
        state = VectorField({
            name: base_state[name] * factor for name in fields})
        writer.write(Carry(state, clock_at(it, start_date=start_date)))
    writer.close()


# ================================================================
#  Store 1: 2D cell-centered scalar, 5 time steps
# ================================================================
def make_2d_scalar():
    mx = IntervalMesh(16, (0.0, 1.0), name="x")  # periodic
    my = IntervalMesh(16, (0.0, 1.0), name="y")  # periodic
    grid = Grid((mx, my))
    temp = grid.create_field(
        init=lambda x, y: jnp.sin(2 * jnp.pi * x) * jnp.cos(2 * jnp.pi * y),
        metadata=FieldMetadata.create(
            name="temp", long_name="Temperature", units="K"))
    run_writer(OUT / "2d_scalar.zarr", VectorField({"temp": temp}),
               range(5),
               attrs={"title": "CDFViewer fixture: 2D scalar"})


# ================================================================
#  Store 2: 3D staggered vector (u, v, w) + centered scalar
# ================================================================
def make_3d_vector():
    mx = IntervalMesh(8, (0.0, 1.0), name="x")  # periodic
    my = IntervalMesh(8, (0.0, 1.0), name="y")  # periodic
    mz = IntervalMesh(8, (0.0, 1.0), periodic=False, name="z")
    grid = Grid((mx, my, mz))
    u = grid.create_field(
        mx.right * my.center * mz.center,
        init=lambda x, y, z: jnp.sin(2 * jnp.pi * x) + 10.0 * y + 100.0 * z,
        metadata=FieldMetadata.create(
            name="u", long_name="Zonal velocity", units="m/s"))
    v = grid.create_field(
        mx.center * my.right * mz.center,
        init=lambda x, y, z: jnp.cos(2 * jnp.pi * y) + 10.0 * z + 100.0 * x,
        metadata=FieldMetadata.create(
            name="v", long_name="Meridional velocity", units="m/s"))
    w = grid.create_field(
        mx.center * my.center * mz.outer,  # z walls -> 9 outer nodes
        init=lambda x, y, z: z * (1.0 - z) + 10.0 * x + 100.0 * y,
        metadata=FieldMetadata.create(
            name="w", long_name="Vertical velocity", units="m/s"))
    p = grid.create_field(
        init=lambda x, y, z: x * y * z,
        metadata=FieldMetadata.create(
            name="p", long_name="Pressure", units="Pa"))
    state = VectorField({"u": u, "v": v, "w": w, "p": p})
    run_writer(OUT / "3d_vector.zarr", state, range(3),
               attrs={"title": "CDFViewer fixture: 3D staggered vector"})


# ================================================================
#  Store 3: fields on different function spaces side by side
# ================================================================
def make_mixed_spaces():
    mx = IntervalMesh(8, (0.0, 2.0), name="x")  # periodic
    my = IntervalMesh(6, (0.0, 1.0), periodic=False, name="y")
    grid = Grid((mx, my))
    phi = grid.create_field(  # cell centers: dims (x, y)
        init=lambda x, y: x + y,
        metadata=FieldMetadata.create(
            name="phi", long_name="Cell-centered scalar", units="1"))
    fx = grid.create_field(  # x faces: dims (x_right, y)
        mx.right * my.center,
        init=lambda x, y: 2.0 * x - y,
        metadata=FieldMetadata.create(
            name="fx", long_name="x-face flux", units="m2/s"))
    fy = grid.create_field(  # y outer nodes: dims (x, y_outer), 7 pts
        mx.center * my.outer,
        init=lambda x, y: x * y + 1.0,
        metadata=FieldMetadata.create(
            name="fy", long_name="y-face flux", units="m2/s"))
    state = VectorField({"phi": phi, "fx": fx, "fy": fy})
    run_writer(OUT / "mixed_spaces.zarr", state, range(2),
               attrs={"title": "CDFViewer fixture: mixed function spaces"})


# ================================================================
#  Store 4: 1D grid, single time step
# ================================================================
def make_1d_single_step():
    mx = IntervalMesh(16, (0.0, 4.0), name="x")  # periodic
    grid = Grid((mx,))
    h = grid.create_field(
        init=lambda x: jnp.sin(jnp.pi * x / 2.0),
        metadata=FieldMetadata.create(
            name="h", long_name="Surface elevation", units="m"))
    run_writer(OUT / "1d_single_step.zarr", VectorField({"h": h}),
               range(1),
               attrs={"title": "CDFViewer fixture: 1D, one time step"})


# ================================================================
#  Store 5: time-chunked, calendar time axis, append mode
# ================================================================
def make_time_chunked_append():
    start = np.datetime64("2020-01-01T00:00:00")
    mx = IntervalMesh(8, (0.0, 1.0), name="x")  # periodic
    my = IntervalMesh(8, (0.0, 1.0), name="y")  # periodic
    grid = Grid((mx, my))
    c = grid.create_field(
        init=lambda x, y: jnp.exp(-((x - 0.5) ** 2 + (y - 0.5) ** 2)
                                  / 0.02),
        metadata=FieldMetadata.create(
            name="c", long_name="Tracer concentration", units="kg/m3"))
    state = VectorField({"c": c})
    path = OUT / "time_chunked_append.zarr"
    # first segment: iterations 0..2 (creates the store, time chunk 2)
    run_writer(path, state, range(3), start_date=start,
               chunks={"time": 2},
               attrs={"title":
                      "CDFViewer fixture: chunked time + append"})
    # second segment: append iterations 3..4 (longer time axis)
    run_writer(path, state, range(3, 5), start_date=start, mode="a",
               chunks={"time": 2})


# ================================================================
#  Verification summary
# ================================================================
def verify():
    import json

    import xarray as xr
    for store in sorted(OUT.glob("*.zarr")):
        # Only the Writer's zarr-v2 stores; skip e.g. the v3 fixture from
        # generate_zarr_v3_fixture.py (no .zgroup, zarr.json metadata).
        if not (store / ".zgroup").is_file():
            continue
        ds = xr.open_zarr(store, consolidated=False)
        print("=" * 64)
        print(store.name)
        print("  dims:", dict(ds.sizes))
        print("  coords:", {
            k: (float(ds[k].min()), float(ds[k].max()))
            if ds[k].dtype.kind != "M"
            else (str(ds[k].values.min()), str(ds[k].values.max()))
            for k in ds.coords})
        print("  data_vars:", {k: ds[k].dims for k in ds.data_vars})
        for k in ds.data_vars:
            print(f"  {k}.attrs:", dict(ds[k].attrs))
        print("  time.attrs:", dict(ds["time"].attrs),
              ds["time"].encoding.get("units"))
        print("  global attrs:", dict(ds.attrs))
        print("  .zmetadata exists:",
              (store / ".zmetadata").exists())
        var = next(iter(ds.data_vars))
        zarray = json.loads((store / var / ".zarray").read_text())
        print(f"  {var}/.zarray:", zarray)
        for k in ds.data_vars:
            values = ds[k].values
            idx = (0,) * values.ndim
            mid = tuple(s // 2 for s in values.shape)
            last = tuple(s - 1 for s in values.shape)
            for i in (idx, mid, last):
                print(f"  ground truth {k}{i} = {values[i]!r}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    make_2d_scalar()
    make_3d_vector()
    make_mixed_spaces()
    make_1d_single_step()
    make_time_chunked_append()
    verify()


if __name__ == "__main__":
    main()
