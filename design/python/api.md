# Python API — open questions

Each question lists the options, a recommendation, and a `Decision:` line.
Settled questions move into `decisions.md` as D-entries when the work plan is
written.

Facts the questions rest on (from the code as of v2026.8.2):

- CLI options: `files...`, `-v/--var`, `-x/--x-axis`, `-y/--y-axis`,
  `-z/--z-axis`, `-p/--plot_type`, `--over` (repeatable), `--over-plot`
  (repeatable, matched by position), `--kwargs`, `--dims`, `-a/--ani-dim`,
  `-s/--saveoptions`, `-g/--grid`, `--theme`; flags `--savefig`, `--record`,
  `--menu`, `--use-local`, `--no-grid-search`, `--no-summary`.
- Save options (`-s`): `filename`, `framerate` (30), `px_per_unit` (1),
  `range` (a Julia range of frames, recording only).
- Keyword values are parsed by `Parsing.parse_value`: quoted strings,
  `:symbols`, numbers, `true/false/nothing`, tuples, arrays, ranges `a:b`,
  and anything else as a Julia expression in a sandbox with Makie, Colors
  and Dates (`Makie.Symlog10(1e-2)`, `RGBf(1,0,0)`, `Day(1)`).
- Makie accepts colors and colormaps as strings, so `colormap="balance"`
  and `color="black"` work without symbols.
- Without `--savefig`/`--record` the app starts its REPL. With a non-TTY
  stdin it runs a basic line loop: prints `CDFViewer> `, reads a line,
  evaluates it, prints the result via `@info` (stderr), and **exits on
  EOF** — so a viewer started from Python with a closed or exhausted stdin
  closes immediately. Keeping a pipe open keeps the window open, and
  writing lines to it drives the session.

## Q1 — Shape of the surface

- (A) Functions: `show(...)`, `savefig(...)`, `record(...)` sharing the
  selection parameters, plus `command(...)` returning the argv list and
  `run(argv)` as a raw passthrough.
- (B) A spec object: `Plot(path, var=..., ...)` with `.show()`,
  `.savefig()`, `.record()`, `.command()`. One spec, several outputs.
- (C) Both, (B) implemented on top of (A).

Recommendation: (A). Keyword functions are what Python users reach for,
`command()` gives the copy-pasteable CLI line for a shell or a paper, and a
spec object can be added later without breaking (A).

Decision (2026-08-22): `savefig()`, `record()`, `command()` and a `Session`
class. No `show()`: a terminal hand-over is useless in a notebook (the
kernel's stdin is not the terminal, the REPL hits EOF at once), and in a
terminal the CLI does the job. No spec object.

- `savefig()` / `record()`: one process per call (`--savefig` / `--record`,
  headless). `record()`/`savefig()` are `run(command(...))`.
- `command(...)`: the same parameters, returns a `Command` — a `list[str]`
  (argv, binary resolved) with a `.shell` property (`shlex.join`). For job
  scripts, papers, dry runs, custom runners. Counterpart of `Session.export()`.
- `Session(path, ...)`: one process kept alive, the app's basic REPL driven
  over a stdin pipe. A live object, not a context manager (the `with` form
  exists for scripts but is optional): the window stays open while the
  object lives; `close()`, `del`, kernel exit or crash end it (EOF). The
  kernel is never blocked — the viewer has its own process and GL loop, so
  mouse interaction and Python calls act on the same state. A background
  reader thread drains the app's output at all times (a full pipe would
  block the app and freeze its GUI); command output is the return value of
  the call, unsolicited `Warning:` lines become `CDFViewerWarning`. Methods
  mirror the REPL vocabulary: `var`, `plot`, `axes(x=, y=, z=)`, `isel`,
  `sel`, `over`, `set(**kwargs)`, `delete`, `get`, `savefig`, `record`,
  `theme`, `reset`, `export`, window `show()`/`hide()`, `send(line)`,
  `close()`, plus `png()` and `_repr_png_` (the current figure inline in a
  notebook cell). `Session(..., visible=False)` sends `hide` after startup;
  a Julia-side `--hidden` start flag is a possible later refinement.
- Spike before the work plan: the prompt arrives unbuffered through the
  pipe; `savefig`/`record` return the prompt only once the file is written;
  what a failed command looks like in the output.

## Q2 — Parameter names

Mirror the CLI, snake_case, one parameter per CLI option:

| Parameter | CLI | Type |
|---|---|---|
| `path` | `files` | `str | PathLike | Sequence[...]` (several NetCDF files, or one zarr store) |
| `var` | `-v` | `str` (`"u,v"` names a vector pair, as on the CLI) |
| `x`, `y`, `z` | `-x -y -z` | `str` |
| `plot` | `-p` | `str` |
| `anim` | `-a` | `str` |
| `dims` | `--dims` | `dict[str, int]` |
| `over` | `--over`/`--over-plot` | `list[str | tuple[str, str]]` — `"temp"` or `("u,v", "quiver")` |
| `kwargs` | `--kwargs` | `dict[str, Any]` (Q3) |
| `grid` | `-g` | `str | PathLike` |
| `grid_search` | `--no-grid-search` | `bool = True` |
| `theme` | `--theme` | `str` |
| `use_local` | `--use-local` | `bool = False` |
| `menu` | `--menu` | `bool = False`, `show()` only |
| `summary` | `--no-summary` | `bool = False` for `show()`; one-shot calls always pass `--no-summary` |

Not recommended: letting unknown `**extra` flow into `--kwargs`. Plot
keywords can be named after coordinates (`x=(0, 100, 200)` sets a coordinate
range), which clashes with the `x` axis parameter.

Decision (2026-08-22): as close to the CLI as possible. One parameter per
option, named after the option's long form (its short form for `-x -y -z`,
whose long forms `--x-axis` read badly as `x_axis` and match the REPL
commands `x`, `y`, `z`):

| Parameter | CLI | Type |
|---|---|---|
| `path` | `files` | `str | PathLike | Sequence[...]` |
| `var` | `-v/--var` | `str` |
| `x`, `y`, `z` | `-x -y -z` | `str` |
| `plot_type` | `-p/--plot_type` | `str` |
| `ani_dim` | `-a/--ani-dim` | `str` |
| `dims` | `--dims` | `dict[str, int]` |
| `over` | `--over` | `list[str]` |
| `over_plot` | `--over-plot` | `list[str]`, matched to `over` by position; a missing entry gets the default type, as on the CLI |
| `kwargs` | `--kwargs` | `dict[str, Any]` (Q3) |
| `grid` | `-g/--grid` | `str | PathLike` |
| `theme` | `--theme` | `str` |
| `no_grid_search` | `--no-grid-search` | `bool = False` |
| `use_local` | `--use-local` | `bool = False` |
| `menu` | `--menu` | `bool = False`, `Session` only |
| `no_summary` | `--no-summary` | `bool = False`, `Session` only; one-shot calls always pass it |

`kwargs=dict(...)` is the only way into `--kwargs`; no `**extra`
passthrough. Flags keep their CLI names even where Python would prefer the
positive form (`no_grid_search=True`), so the signature reads like `--help`.

## Q3 — Value formatting for `kwargs` (and save options)

| Python | Julia text |
|---|---|
| `str` | `"..."` with `"` and `\` escaped |
| `bool` | `true` / `false` |
| `None` | `nothing` |
| `int`, `float` | `repr`; `inf`/`nan` → `Inf`/`NaN` |
| `tuple` | `(a, b)`; one element → `(a,)` |
| `list` | `[a, b]` |
| `range(a, b, s)` | `a:s:b-1`? — Python ranges are half-open; see below |
| `datetime.datetime`/`date` | `DateTime("2026-08-22T00:00:00")` / `Date(...)` |
| `cdfviewer.sym("balance")` | `:balance` |
| `cdfviewer.raw("Makie.Symlog10(1e-2)")` | verbatim |
| numpy scalars | via `.item()` |

Nested values format recursively (`color=(sym("red"), 0.6)` → `(:red, 0.6)`).

Ranges: either translate `range` with the half-open correction, or refuse
`range` and point to `raw("0:10")`. Recommendation: refuse — a silent
off-by-one in a frame range is worse than a two-line hint.

Decision (2026-08-22): the table as it stands, recursively for nested
values; `sym()` and `raw()` helpers. `range` and `slice` objects are
refused with a `TypeError` naming `raw("0:10")` and the inclusive
convention. Any other unknown type is a `TypeError` too (no `str()`
fallback: a silently stringified object fails far away, inside the app).

## Q4 — Save options as parameters

`savefig(..., filename, px_per_unit=1)` and
`record(..., filename, framerate=30, px_per_unit=1, frames=None)`.
`frames` takes a `(start, stop)` or `(start, step, stop)` tuple in the
app's 1-based inclusive convention and becomes `range=start:step:stop`.
Only four save options exist, so no catch-all `save=dict()`.

`filename` is resolved to an absolute path against Python's cwd before it
is handed over (the app may `cd` for `--use-local`), and the absolute
`pathlib.Path` is returned. Recommendation: `filename` required on both —
a default name would surprise more than it helps.

Decision (2026-08-22): `savefig(..., filename=None, px_per_unit=None)`,
`record(..., filename=None, framerate=None, px_per_unit=None, frames=None)`,
and `Session.savefig` / `Session.record` with the same options (REPL
`savefig filename=..., px_per_unit=...` / `record ...`). `frames` takes
`(start, stop)` or `(start, step, stop)`, 1-based inclusive, written as
`range=start:step:stop`. `filename` is **optional, as on the CLI**: the
app picks its standard name, and the wrapper returns the absolute `Path`
read from the app's `Saved ... to <path>` line (stderr is captured
anyway; the Julia side keeps that line stable). A given `filename` is
`~`-expanded and made absolute against Python's cwd first. Only options
that were set are passed, so the app's defaults stay the single source of
truth.

## Q5 — `show()` semantics

- (A) Blocking, terminal handed over: inherit stdin/stdout; the REPL runs
  in the user's terminal; returns when the viewer exits. Only works from a
  terminal; in a notebook the REPL hits EOF at once and the window closes.
- (B) Non-blocking handle: spawn with a stdin pipe held open, return a
  `Viewer` with `.send(line) -> str` (writes a REPL command, reads until
  the next `CDFViewer> ` prompt, returns the output), `.close()`,
  `.wait()`, context-manager support, `.pid`. Works from scripts and
  notebooks; the window stays until `close()` or the process is collected.
- (C) (B) by default, (A) with `show(..., interactive=True)`.

Recommendation: (C). (B) costs nothing on the Julia side — the basic REPL
already exists — and makes the package useful from a notebook; (A) is what
a terminal user expects. Capture stderr into the same pipe so `.send()`
returns what `@info` printed. (The same `Viewer` is the "session mode"
discussed earlier; it comes for free here.)

Decision (2026-08-22): resolved by Q1 — there is no `show()`; `Session`
is option (B) as a long-lived object. Option (A) is pointless in a
notebook (the kernel's stdin is not the terminal) and redundant in a
terminal (the CLI).

## Q6 — Errors and warnings

- Non-zero exit → `CDFViewerError(returncode, argv, stderr_tail)`; message
  shows the last stderr lines.
- The app's `Warning:`/`Error:` log lines on stderr with exit 0 (e.g. a
  keyword line reverted) → `warnings.warn(text, CDFViewerWarning)`, one per
  log record, so a silently ignored keyword is not silent in Python.
- `quiet=True` drops the `[ Info: ...]` banner lines from the terminal;
  stderr is always captured for the two points above.

Recommendation: all three.

Decision (2026-08-22): all three, and `Error:` records **raise**
`CDFViewerError` after the call completes (the output file, if any, is
left in place); in a `Session` the command's output is checked the same
way and the session stays alive. Default is quiet (everything captured,
only the warnings above surface); `verbose=True` streams the app's output
live to stderr, which is where the recording progress bar shows.

Addendum to Q4 (2026-08-22): the unmerged branch `fix/output-overwrite`
(commit f52d96f) is merged as part of this work. It makes a save or a
recording write over an existing file by default, with `overwrite=false`
keeping the `name(1).ext` numbering, on both REPL commands and in `-s`.
`overwrite` is therefore the fifth save option of `savefig()`,
`record()` and the `Session` methods, default the app's (`True`). The
returned `Path` is still read from the app's `Saved ... to` line.

## Q7 — In-memory input: xarray Datasets, DataArrays, numpy arrays

Asked for explicitly (2026-08-22): `path` may also be an
`xarray.Dataset`, an `xarray.DataArray` or a numpy array. Under the hood
the object is written to a temporary file that the app then opens.

Points to settle:

- **Writer.** A `Dataset` goes through `to_netcdf` (needs a NetCDF
  backend in the user's environment: `netCDF4` or `h5netcdf`; `scipy`
  only writes NetCDF3) or `to_zarr` (needs `zarr`). Pick the first
  available, error with a hint naming both if none is. A `DataArray`
  becomes a one-variable `Dataset` (`to_dataset(name=da.name or "data")`)
  and `var` defaults to that name. A numpy array is wrapped in a
  `DataArray` with dims `dim_0, dim_1, ...` (optionally named via a
  `dims=`-like argument? — `dims` is taken by the index selection; maybe
  `cv.array(arr, dims=("time", "y", "x"), coords=...)` as a tiny helper
  returning a DataArray) — which makes xarray a requirement for in-memory
  input, not for the package. Dask-backed arrays are computed by the write.
- **Temp location and size.** `tempfile.gettempdir()` honours `TMPDIR`,
  but `/tmp` is often a small tmpfs and an in-memory dataset can be GBs.
  Provide `CDFVIEWER_TMPDIR` / `configure(tmpdir=...)`; document it.
- **Lifetime.** One-shot calls delete the file afterwards; a `Session`
  deletes it on `close()`. The app keeps the file open, so deletion must
  follow the process exit.
- **Fidelity.** Attributes (`units`, `long_name`, `standard_name`) and
  coordinates survive the round trip, so labels and unit handling work as
  for a file on disk.

Recommendation: yes to all three inputs via xarray; xarray and a NetCDF
backend are optional dependencies (`pip install cdfviewer[xarray]`).

Decision:

## Q8 — Version policy

`cdfviewer.__version__` is the app version. A `PATH` binary of another
version warns once per process (`CDFViewerWarning`), never errors; the
managed bundle is always the matching version.

Decision:

## Q9 — Logging and progress

Package messages (download, extraction, resolution) go through
`logging.getLogger("cdfviewer")`; the first-use download additionally prints
a progress indicator to stderr when it is a TTY.

Decision:

## Q10 — Documentation

A `docs/src/usage/python.md` page (install, the three functions, `Viewer`,
value formatting table, `command()`) and a `python/README.md` for PyPI.
Type hints throughout, `py.typed` shipped.

Decision:
