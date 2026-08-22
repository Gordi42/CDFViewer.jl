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

Decision:

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

Decision:

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

Decision:

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

Decision:

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

Decision:

## Q6 — Errors and warnings

- Non-zero exit → `CDFViewerError(returncode, argv, stderr_tail)`; message
  shows the last stderr lines.
- The app's `Warning:`/`Error:` log lines on stderr with exit 0 (e.g. a
  keyword line reverted) → `warnings.warn(text, CDFViewerWarning)`, one per
  log record, so a silently ignored keyword is not silent in Python.
- `quiet=True` drops the `[ Info: ...]` banner lines from the terminal;
  stderr is always captured for the two points above.

Recommendation: all three.

Decision:

## Q7 — Dataset input beyond paths

Accept an `xarray.Dataset` (duck-typed: anything with `.to_netcdf`) by
writing it to a temporary NetCDF file that lives as long as the call (or
the `Viewer`). No xarray dependency; purely optional.

Recommendation: yes — it is ~20 lines and the usual case is an in-memory
result one wants to look at.

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
