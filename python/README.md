# cdfviewer

Python interface to [CDFViewer](https://github.com/Gordi42/CDFViewer.jl),
an interactive viewer for NetCDF files and zarr stores.

Render a figure or an animation from a script, build a command line
without running it, or keep a viewer open from a notebook cell and drive
it while you look at it. Everything runs in the `cdfviewer` application
itself, and every parameter is named after the command-line option it
stands for.

```bash
pip install cdfviewer
```

The application binary is found through `CDFVIEWER_BIN`, then on `PATH`,
and otherwise downloaded on first use (Linux x86_64). `pip install
"cdfviewer[xarray]"` adds what is needed to pass xarray objects instead of
file paths.

## Save a figure

```python
import cdfviewer as cv

fig = cv.savefig(
    "demo.nc",
    var="temperature", x="lon", y="lat", plot_type="heatmap",
    kwargs={"colormap": "balance", "colorrange": (-2, 30)},
    filename="temperature.png",
)
```

`fig` is the path of the file that was written -- path-like, with the
`pathlib.Path` in `fig.path` -- and it draws the figure when it is the
value of a notebook cell.

## Record an animation

```python
video = cv.record(
    "demo.nc",
    var="temperature", x="lon", y="lat", plot_type="heatmap",
    ani_dim="time",
    filename="temperature.mp4", framerate=25,
)
```

In a notebook the recording plays inline, embedded in the notebook up to
`cv.configure(embed_limit=...)` megabytes (20 by default).

## Keep a viewer open

```python
s = cv.Session("demo.nc", var="temperature", x="lon", y="lat",
               plot_type="heatmap")

s.set(colormap="viridis")   # the open window updates
s.isel(time=5)
s.savefig("frame.png")
s.close()
```

The window stays open while the session lives, and your Python process is
never blocked. Constructing a `Session` on a dataset that already has one
adjusts that viewer instead of opening a second, so re-running a notebook
cell updates the plot you are looking at.

## Development

The package lives in `python/` of the CDFViewer.jl repository and follows
the conventions of [fridom](https://github.com/Gordi42/FRIDOM): src layout,
[uv](https://docs.astral.sh/uv/), ruff with `select = ["ALL"]`, NumPy-style
docstrings, function-based tests that mirror the source tree, and a
coverage gate of 95 % measured without a real binary.

```bash
cd python
uv sync --extra dev            # environment with xarray, netCDF4, zarr, ruff, pytest
uv run ruff check src tests    # lint (also the pre-commit hook at the repo root)
uv run pytest --cov            # unit tests against the fake binary, coverage gate
CDFVIEWER_BIN=/path/to/cdfviewer uv run pytest -m binary   # against a real app
```

The unit tests never start the real app: `tests/fake_cdfviewer.py` stands
in for it, answering `--version`, `--savefig`/`--record` and the REPL the
way the app does. The tests marked `binary` run only when `CDFVIEWER_BIN`
names a real `cdfviewer`; the release workflow runs them against the
bundle it has just built. The package version in
`src/cdfviewer/_version.py` must equal the `version` in the repository's
`Project.toml` — one tag releases the app, the bundle and the wheel.

## Documentation

The full page -- installing, the binary search, every parameter, keyword
values, in-memory data, errors -- is in the manual:
<https://gordi42.github.io/CDFViewer.jl/usage/python/>.

MIT licensed, like CDFViewer.jl itself.
