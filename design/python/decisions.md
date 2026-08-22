# Settled decisions

Dates are when the decision was taken.

## D1 — A pure-Python wrapper, not in-process bindings (2026-08-22)

The package drives the `cdfviewer` binary through `subprocess`. No juliacall
/ PyJulia: that would need a Julia install and a GLMakie compile inside the
Python environment (first-use hitches, which this project treats as the
top priority to avoid), cannot reuse the PackageCompiler bundle, and the app
is built around a REPL and a controller rather than a callable API.

## D2 — Name, location, versioning (2026-08-22)

- PyPI name `cdfviewer` (free as of 2026-08-22), import name `cdfviewer`.
- Lives in this repository under `python/` with its own `pyproject.toml`
  (installable from git with `pip install "cdfviewer @ git+...#subdirectory=python"`).
- The package version **is** the app version (CalVer `YYYY.M.PATCH`), read
  from the repo's `Project.toml` at build time or kept in sync by the
  release job. One tag releases the Julia app, the bundle and the wheel.
- No required third-party dependencies. Python >= 3.10.

## D3 — Binary resolution order (2026-08-22)

First hit wins:

1. Explicit: `CDFVIEWER_BIN=/path/to/cdfviewer` or `cdfviewer.configure(bin=...)`.
2. `cdfviewer` on `PATH` — **skipping the package's own launcher** (the
   console script is itself a `cdfviewer` on `PATH`; finding it would recurse).
3. A managed bundle at `$XDG_CACHE_HOME/cdfviewer/<version>/cdfviewer/bin/cdfviewer`
   (default `~/.cache/cdfviewer/...`). Missing → downloaded on first use,
   with a one-line message and a progress indicator on stderr.

A `PATH` binary of another version is used, with a warning once per process
(needs a `--version` flag on the Julia side, D5).

## D4 — The managed download (2026-08-22)

- Source: the GitHub release asset of the package's own version,
  `https://github.com/Gordi42/CDFViewer.jl/releases/download/v<version>/cdfviewer-linux-x86_64.tar.zst`.
- Verified against a `.sha256` asset uploaded by the release job (D5) before
  extraction; a mismatch deletes the download and raises.
- Extracted with `tar --zstd -x` (the bundle is Linux-only and every Linux
  `tar` of the last years has zstd); a missing zstd gives a clear error.
- Linux x86_64 only. On any other platform step 3 does not exist and the
  error says so: install CDFViewer.jl and put `cdfviewer` on `PATH`.
- Management commands live under `python -m cdfviewer`, not under the
  `cdfviewer` launcher (which stays a pure passthrough so a file named
  `install` is still a file): `install [--version V] [--force]`, `which`,
  `prune` (delete all but the current version), `uninstall`.

## D5 — Console script and Julia-side changes (2026-08-22)

- `[project.scripts] cdfviewer = "cdfviewer._launcher:main"`: resolve the
  binary (D3), then `os.execv` it with the arguments untouched. The Python
  process is replaced, so the TTY, stdin, Ctrl-C and exit codes pass through
  and the interactive REPL behaves as with the native binary.
- Julia side: a `--version` flag printing `cdfviewer <version>` and exiting;
  the release job uploads `cdfviewer-linux-x86_64.tar.zst.sha256` next to the
  bundle and publishes the wheel to PyPI from the same tag.

## D6 — API (2026-08-22, details in `api.md`)

- Surface: `savefig()`, `record()`, `command()` (argv as a `Command`
  list with `.shell`), and the `Session` class. No `show()`.
- Parameters named after the CLI options (`var`, `x`, `y`, `z`,
  `plot_type`, `ani_dim`, `dims`, `over`, `over_plot`, `kwargs`, `grid`,
  `theme`, `no_grid_search`, `use_local`, `menu`, `no_summary`); no
  `**extra` passthrough.
- Keyword values formatted per the Q3 table with `sym()`/`raw()`; `range`
  and `slice` refused; unknown types are a `TypeError`.
- Save options as parameters: `filename` (optional, as on the CLI),
  `px_per_unit`, `framerate`, `frames=(start[, step], stop)`,
  `overwrite`; the returned `Path` is read from the app's `Saved ... to`
  line. `fix/output-overwrite` merged for this (2026-08-22).
- `CDFViewerError` on non-zero exit and on `Error:` records; `Warning:`
  records become `CDFViewerWarning`; quiet by default, `verbose=True`
  streams.
- In-memory input (`Dataset`, `DataArray`, numpy) via xarray as the
  optional extra; complex data split into `_real`/`_imag` by default,
  `complex="abs"|"real"|"imag"|"phase"` otherwise; `CDFVIEWER_TMPDIR`.
- `Session`: a live object with the reuse contract (registry keyed by
  dataset, declarations applied as diffs), `png()`/`_repr_png_`, methods
  named after the REPL commands, `send()` as the escape hatch.
- Versions warn, never error; `logging.getLogger("cdfviewer")`; docs in
  the Documenter manual; no `py.typed`; Python >= 3.11.

## D7 — Conventions (2026-08-22, details in `conventions.md`)

fridom's layout, ruff config, test and coverage setup (>= 95 % without the
real binary, via a fake-binary fixture), uv, pre-commit; ruff also in CI,
no Codecov, no type checker.
