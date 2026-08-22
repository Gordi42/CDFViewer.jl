# The Python Package

The `cdfviewer` Python package drives the application from Python. It
renders figures and animations from a script, builds command lines without
running them, and keeps a viewer open from a notebook cell so you can plot,
look, and change the plot without leaving the notebook.

It is a wrapper, not a rewrite. Every call ends in the same `cdfviewer`
binary the command line runs, so what you can express here is what you can
express on the command line, under the same names.

## Installing

```bash
pip install cdfviewer
```

The package itself has no dependencies. Passing xarray objects instead of
file paths needs xarray and a NetCDF backend, which come with the extra:

```bash
pip install "cdfviewer[xarray]"
```

Python 3.11 or newer is required.

### Finding the application

The package has to find a `cdfviewer` executable. It looks in three places
and takes the first hit.

1. An explicit one: the `CDFVIEWER_BIN` environment variable, or
   `cdfviewer.configure(binary="/path/to/cdfviewer")`.
2. A `cdfviewer` on your `PATH` -- a bundle you unpacked yourself, or a
   Julia installation wrapped in a script (see
   [Installation](../installation.md)). The package's own launcher is
   skipped, so it does not find itself.
3. A managed bundle under `~/.cache/cdfviewer/<version>/`. If it is not
   there, it is downloaded from the GitHub release of the package's own
   version on first use, checked against the release's SHA-256 file, and
   unpacked. `CDFVIEWER_CACHE` moves that directory elsewhere, which
   matters on machines with a small home quota.

The managed download is **Linux x86_64 only**, because that is the only
platform the bundle is built for. Elsewhere, step 3 does not exist: install
CDFViewer.jl as a Julia package and put a `cdfviewer` command on your
`PATH`.

You can manage the download yourself:

```bash
python -m cdfviewer install          # fetch the matching bundle now
python -m cdfviewer install --version 2026.8.1 --force
python -m cdfviewer which            # print the binary that would be used
python -m cdfviewer prune            # delete every bundle but the current one
python -m cdfviewer uninstall        # delete the managed bundle
```

These live under `python -m cdfviewer` rather than under the `cdfviewer`
command, which stays a plain pass-through to the application: installing the
package gives you the same `cdfviewer` command line documented in the rest
of this manual.

A binary found on `PATH` whose version differs from the package's is used
anyway, with one warning per process. Versions here are a hint, never a
gate.

## Saving a figure

`savefig` renders one figure headlessly and returns the file it wrote.

```python
import cdfviewer as cv

path = cv.savefig(
    "demo.nc",
    var="temperature", x="lon", y="lat", plot_type="heatmap",
    filename="temperature.png",
)
print(path)     # /home/you/work/temperature.png
```

Every selection parameter is named after its command-line option, so a
working command line translates a word at a time:

| Parameter | Option | Value |
|:----------|:-------|:------|
| `path` | `files` | a path, or a sequence of paths |
| `var` | `-v` | the variable, `"u,v"` for a vector pair |
| `x`, `y`, `z` | `-x -y -z` | the axis variables |
| `plot_type` | `-p` | `"heatmap"`, `"contour"`, `"line"`, ... |
| `ani_dim` | `-a` | the dimension to animate |
| `dims` | `--dims` | `{"time": 5, "level": 0}` |
| `over` | `--over` | `["salinity", "u,v"]` |
| `over_plot` | `--over-plot` | `["contour", "quiver"]`, by position |
| `kwargs` | `--kwargs` | plot keywords, see below |
| `grid` | `-g` | a grid file for unstructured data |
| `theme` | `--theme` | `"dark"`, `"ggplot2"`, ... |
| `no_grid_search` | `--no-grid-search` | `True` to switch the search off |
| `use_local` | `--use-local` | `True` to stage output locally |

The flags keep their command-line names even where Python would rather have
the positive form: `no_grid_search=True` is the same switch as
`--no-grid-search`, and the signature reads like `--help`.

Relative paths are resolved against Python's working directory before they
are handed over, both for the data and for the output, so `use_local=True`
does not move your files somewhere unexpected.

## Recording an animation

`record` is `savefig` with an animated dimension and a video file.

```python
path = cv.record(
    "demo.nc",
    var="temperature", x="lon", y="lat", plot_type="heatmap",
    ani_dim="time",
    filename="temperature.mp4", framerate=25,
)
```

## The save options

Five options control the output, on both functions and on the `Session`
methods of the same name. They are the same options the REPL's `savefig`
and `record` commands take (see
[Saving and Recording](saving.md)); only the ones you pass are handed over,
so the application's own defaults stay the single source of truth.

- `filename` -- the output path. Optional, as on the command line: without
  it the application picks its standard name. Either way the absolute path
  of the file that was written comes back as a `pathlib.Path`.
- `px_per_unit` -- the resolution multiplier. `2` doubles the pixel
  resolution at the same layout.
- `framerate` -- frames per second (`record` only, default 30).
- `frames` -- which frames to record (`record` only), as `(start, stop)` or
  `(start, step, stop)`. The bounds are 1-based and **inclusive**, as
  everywhere in the application: `frames=(1, 12)` records twelve frames,
  and `frames=(1, 2, 21)` records every second frame of the first twenty-one.
- `overwrite` -- what a name that is already taken means. The default
  writes over it; `overwrite=False` keeps the earlier file and writes
  `name(1).png` instead.

## Building a command line

`command` takes the same parameters and runs nothing. It returns a
`Command`, which is a `list[str]` of argv with the resolved binary in
front, and a `.shell` property giving the line quoted for a shell.

```python
cmd = cv.command(
    "demo.nc",
    var="temperature", x="lon", y="lat", plot_type="heatmap",
    kwargs={"colormap": "balance", "levels": 20},
    savefig=True, filename="temperature.png",
)
print(cmd.shell)
```

Use it for job scripts, for a line to paste into a paper or an issue, and
for dry runs. Being a plain list, it also goes straight into
`subprocess.run(cmd)` if you want to run it yourself. It is the counterpart
of the REPL's `export` command and of `Session.export`.

## A live viewer

`Session` starts a viewer and keeps it running. The object is the viewer:
the window is open as long as the session lives, and your Python process is
never blocked -- the application has its own process and its own event loop,
so the mouse and your Python calls act on the same figure.

```python
s = cv.Session("demo.nc", var="temperature", x="lon", y="lat",
               plot_type="heatmap")

s.set(colormap="viridis", colorrange=(-2, 30))
s.isel(time=5)
s.savefig("frame.png")
s.close()
```

`with cv.Session(...) as s:` works too and closes at the end of the block,
but it is the exception: a session that closes when the cell finishes is of
little use in a notebook.

### Re-running the cell

Constructing a `Session` *declares a state*; it does not necessarily start
a process. Sessions are held in a registry keyed by the dataset, so a
second `Session` on the same file returns the viewer that is already open
and adjusts it to the new declaration instead of opening a second window.
Editing a cell and running it again therefore updates the plot you are
looking at.

Only what changed since the last declaration is sent, in the application's
setup order. Keywords you set by hand -- with the mouse, the menu, or
`s.set()` -- are left alone, because the declaration never mentioned them.
Keywords that a previous declaration did set and this one dropped are
deleted. Zoom, window position and playback survive, unless the change is
one the application rebuilds the axis for (the plot type or the axes).

Pass `reuse=False` for a second, independent viewer on the same data.
`cv.sessions()` lists the live ones and `cv.close_all()` ends them; they
also end when the interpreter exits, when you `close()` them, or when you
close the window.

### The methods

They mirror the [REPL commands](../reference/commands.md):

```python
s.var("salinity")           # v salinity
s.plot("contourf")          # p contourf
s.axes(x="lon", y="lat")    # x lon / y lat
s.isel(time=5)              # isel time 5
s.sel(level=100.0)          # sel level 100.0
s.over("u,v", "quiver")     # over u,v quiver
s.over(None, layer=2)       # remove the overlay again
s.set(colormap="balance")   # colormap=:balance
s.delete("colorrange")      # del colorrange
s.get("colormap")           # the value, as the app reports it
s.theme("dark")             # theme dark
s.reset()                   # reset
s.export()                  # the CLI line reproducing this state
s.hide(); s.show()          # close and reopen the figure window
s.send("v temperature")     # anything the REPL understands
```

`send` is the escape hatch: it writes one line to the application's prompt
and returns what it printed. Anything the REPL grows that the package has
not caught up with is reachable through it.

### In a notebook

`s.png()` returns the current figure as PNG bytes, and a session displays
itself as that image when it is the value of a cell:

```python
s = cv.Session("demo.nc", var="temperature", x="lon", y="lat",
               plot_type="heatmap")
s     # the figure, inline in the notebook
```

`visible=False` keeps the window closed and gives you a viewer that only
ever draws into the notebook.

## Keyword values

`kwargs` and `s.set()` take Python values and translate them to what the
application's keyword line expects.

| Python | Julia |
|:-------|:------|
| `"balance"` | `"balance"` |
| `True`, `False` | `true`, `false` |
| `None` | `nothing` |
| `20`, `1.5` | `20`, `1.5` |
| `float("inf")`, `float("nan")` | `Inf`, `NaN` |
| `(0, 30)` | `(0, 30)` |
| `[1, 2, 3]` | `[1, 2, 3]` |
| `datetime(2020, 1, 1)` | `DateTime("2020-01-01T00:00:00")` |
| `date(2020, 1, 1)` | `Date("2020-01-01")` |
| `cv.sym("balance")` | `:balance` |
| `cv.raw("Makie.Symlog10(1e-2)")` | `Makie.Symlog10(1e-2)` |

Nested values are translated the same way, so
`color=(cv.sym("red"), 0.6)` becomes `(:red, 0.6)`.

Makie reads colors and colormaps as strings, so `colormap="balance"` and
`color="black"` need no symbol. `sym()` is for the places that insist on
one, and `raw()` passes Julia source through untouched -- it is evaluated by
the application in the same sandbox the `--kwargs` option uses, with Makie,
Colors and Dates available.

```python
cv.savefig(
    "demo.nc", var="temperature", x="lon", y="lat", plot_type="heatmap",
    kwargs={
        "colormap": "balance",
        "colorrange": (-2, 30),
        "colorscale": cv.raw("Makie.Symlog10(1e-2)"),
        "title": "Sea surface temperature",
    },
    filename="sst.png",
)
```

Python's `range` and `slice` are refused with a `TypeError`. A Python
`range` is half-open and the application's ranges are inclusive, and a
silent off-by-one in a frame range is worse than an error: write
`cv.raw("0:10")`, or use the `frames` option. Any other type the table does
not cover is a `TypeError` as well, rather than being stringified into
something that fails much later inside the application.

## Data that is not on disk

`path` also takes an `xarray.Dataset`, an `xarray.DataArray` or a numpy
array. The object is written to a temporary file, the application opens
that, and the file is deleted once the process is gone -- after the call for
`savefig` and `record`, on `close()` for a `Session`.

```python
import numpy as np
import xarray as xr

ds = xr.Dataset(
    {"temperature": (("lat", "lon"), np.random.randn(90, 180))},
    coords={"lat": np.linspace(-89, 89, 90),
            "lon": np.linspace(-180, 178, 180)},
)
cv.savefig(ds, var="temperature", x="lon", y="lat", plot_type="heatmap",
           filename="random.png")
```

A `DataArray` becomes a one-variable dataset and `var` defaults to its
name. A numpy array is wrapped in a `DataArray` with dimensions `dim_0`,
`dim_1`, ... and no coordinates; wrap it yourself if you want named
dimensions or real coordinates. Attributes and coordinates survive the
round trip, so units and labels come out as they would from a file.
Dask-backed data is computed by the write.

This needs xarray and a writer: `netCDF4` or `h5netcdf` for NetCDF,
otherwise `zarr`. `pip install "cdfviewer[xarray]"` gets you a working
combination.

The temporary file goes where `tempfile.gettempdir()` points, which on many
systems is a small tmpfs. An in-memory dataset can be far larger than that,
so `CDFVIEWER_TMPDIR` (or `cdfviewer.configure(tmpdir=...)`) redirects it:

```bash
export CDFVIEWER_TMPDIR=/scratch/$USER
```

### Complex data

The application has no notion of complex numbers, and neither NetCDF nor
zarr carries them in a form it could read. A complex variable is therefore
split into `name_real` and `name_imag` before the write, with the
attributes copied. Naming a complex variable in `var` selects the real part
and warns.

`complex_as` writes a single real variable under the original name instead:

```python
cv.savefig(ds, var="psi", complex_as="abs", ...)     # or "real", "imag", "phase"
```

`float16` is widened to `float32`, booleans and datetimes are encoded by
xarray and read back by the application, and a variable of `object` dtype
is an error naming the variable.

## Errors and warnings

The application is quiet by default: its output is captured, and only the
two things that need your attention come through.

- A run that fails, or that logs an `Error:`, raises `CDFViewerError`. The
  message carries the last lines of the output; `.returncode`, `.argv` and
  `.output` carry the rest. A file that was written before the error is
  left where it is.
- A `Warning:` from the application -- a keyword it refused and reverted, a
  selection that does not exist -- becomes a Python `CDFViewerWarning`
  through `warnings.warn`, so a silently ignored setting is not silently
  ignored in Python either.

```python
import warnings

with warnings.catch_warnings():
    warnings.simplefilter("error", cv.CDFViewerWarning)
    cv.savefig(...)     # a refused keyword now raises
```

In a `Session` the same check runs on every command, and the session stays
alive afterwards.

`verbose=True` streams the application's output to stderr as it arrives,
which is where the recording progress bar appears. The package's own
messages -- resolving the binary, downloading and unpacking a bundle -- go
through the `cdfviewer` logger:

```python
import logging

logging.getLogger("cdfviewer").setLevel(logging.INFO)
```

The download additionally prints a notice and a progress indicator to
stderr when it is talking to a terminal, however logging is configured: a
first call that quietly stalls for a few hundred megabytes would be worse
than a line of output.
