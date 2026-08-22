# Work plan

How the package gets built: a scaffold first (one commit, by the lead),
then five work packages in parallel (one agent each, on a worktree off
`feat/python-bindings`), then an integration pass. Every agent reads
`decisions.md`, `api.md`, `conventions.md` and this file; the interfaces
below are the contract between packages and are not changed unilaterally —
an agent that needs a change notes it in its report.

## Spike results (2026-08-22, bundle v2026.8.1 over pipes)

- Startup to the first `CDFViewer> ` prompt: ~12 s for the bundle. The
  prompt arrives **unbuffered**, without a trailing newline. Command round
  trips 0.0–1 s.
- Output formats, stderr merged into stdout, in write order:
  - `[ Info: message` — single line;
  - `┌ Info: first line\n│ more\n└ last line` — multi-line block;
  - `┌ Warning: message\n└ @ CDFViewer.Module /path/file.jl:123`;
  - `┌ Error: message\n└ @ CDFViewer.Module /path/file.jl:123`.
  A refused keyword prints a Warning (`... reverting: xunit`) *and* an
  Error (`xunit must be one of (...)`); an unknown command or an invalid
  selection prints a Warning only.
- `savefig` / `record` print `[ Info: Saved figure to <path>` /
  `[ Info: Saved animation to <path>`, and **the file is complete when the
  prompt returns**. Recording prints a ProgressMeter bar first:
  `\rRecording  67%|...|  ETA: 0:00:00\x1b[K` — carriage returns and ANSI
  erase sequences to strip.
- `get colormap` → `[ Info: colormap => :balance`; `export` → a multi-line
  Info block whose last line is the CLI argument string; `hide`/`show`
  work (`Closed figure window.` / `Opened figure window.`).
- Closing stdin → `[ Info: Exiting CDFViewer REPL.` and exit code 0
  within a second.

## Layout

```
python/
  pyproject.toml            # conventions.md; dynamic version from _version.py
  README.md                 # the PyPI page
  uv.lock
  src/cdfviewer/
    __init__.py             # public names, __version__
    _version.py             # __version__ = "<Project.toml version>"
    _errors.py              # CDFViewerError, CDFViewerWarning
    _config.py              # configure(), env vars
    _format.py              # value formatting (WP-A)
    _command.py             # Command, build_args, command() (WP-A)
    _binary.py              # resolve/install/prune/uninstall (WP-B)
    _launcher.py            # console script (WP-B)
    __main__.py             # python -m cdfviewer ... (WP-B)
    _logs.py                # Julia log record parsing (WP-C)
    _data.py                # in-memory input → temp file (WP-C)
    _run.py                 # run(), savefig(), record() (WP-C)
    _session.py             # Session, registry (WP-D)
  tests/
    conftest.py             # fixtures (scaffold)
    fake_cdfviewer.py       # the fake binary (scaffold)
    test_<module>.py        # one per module, mirrors src
    test_init.py            # every public name imports
    binary/test_*.py        # @pytest.mark.binary, real binary only
```

Public names in `__init__.py`: `savefig`, `record`, `command`, `run`,
`Session`, `sessions`, `close_all`, `sym`, `raw`, `configure`,
`CDFViewerError`, `CDFViewerWarning`, `__version__`.

## Scaffold (lead, before the agents start)

`pyproject.toml`, `README.md` stub, `__init__.py`, `_version.py`,
`_errors.py`, `_config.py` (complete — everyone depends on them), a stub
for every other module holding the signatures below with docstrings and
`raise NotImplementedError`, `tests/conftest.py`, `tests/fake_cdfviewer.py`,
`uv.lock`. `uv run pytest` passes on the scaffold (the stubs' tests are
added by the packages). Agents replace stubs; no two packages touch the
same file.

### Fixtures (`tests/conftest.py`)

- `fake_binary(tmp_path, monkeypatch) -> Path`: copies
  `fake_cdfviewer.py` to `<tmp>/bin/cdfviewer` (executable, `#!` python),
  prepends `<tmp>/bin` to `PATH`, clears `CDFVIEWER_BIN`, returns the path.
- `fake_binary_behaviour(tmp_path)`: the fake reads an optional JSON file
  named by `CDFVIEWER_FAKE_CONFIG` — `version`, `exit_code`, `records`
  (extra log lines to print), `fail_save` (exit non-zero on save),
  `startup_delay` — so tests drive error paths without a real app.
- `cache_dir(tmp_path, monkeypatch)`: sets `CDFVIEWER_CACHE` to a temp dir.
- `http_server(tmp_path)`: serves a directory over `http.server` on a free
  port in a thread; yields the base URL. Used for download tests with a
  tiny tarball (`tar --zstd` of a fake bundle) and its `.sha256`.
- `pytest_runtest_setup`: skips `@pytest.mark.binary` tests unless
  `cdfviewer._binary.resolve(download=False)` finds a binary.
- `filterwarnings = ["error"]`: tests that expect a `CDFViewerWarning`
  use `pytest.warns`.

### The fake binary (`tests/fake_cdfviewer.py`)

A Python script emulating what the spike observed: `--version` prints
`cdfviewer <version>` and exits 0; with `--savefig`/`--record` it parses
`-s` for `filename=`, writes a small file (PNG bytes / empty mp4),
prints `[ Info: Saved figure to <abs path>` (or `Saved animation`), and
exits; otherwise it runs the basic REPL: prints the startup Info lines and
`CDFViewer> `, then reads lines and answers: `get <k>` → `[ Info: k =>
<stored or :balance>`; a `key=value` line stores the pairs and prints the
`┌ Info: Current plot settings:` block; `del <k>`; `v`/`p`/`x`/`y`/`z`/
`isel`/`sel`/`over`/`theme`/`reset` → `[ Info: ok`; `savefig ...` /
`record ...` as above; `export` → the Info block with an argv line;
`hide`/`show`; `bogus` → the Warning block; `fail` → a Warning plus an
Error block; `slow <s>` → sleeps; `exit`/EOF → `[ Info: Exiting CDFViewer
REPL.` and exit 0. Every print is flushed. Unknown `-s` keys are ignored.

## Interfaces

### `_errors.py` (scaffold)

```python
class CDFViewerError(RuntimeError):
    def __init__(self, message: str, *, returncode: int | None = None,
                 argv: list[str] | None = None, output: str = "") -> None
    # attributes: returncode, argv, output; str() = message + last 20 lines of output
class CDFViewerWarning(UserWarning): ...
```

### `_config.py` (scaffold)

```python
ENV_BIN = "CDFVIEWER_BIN"; ENV_TMPDIR = "CDFVIEWER_TMPDIR"; ENV_CACHE = "CDFVIEWER_CACHE"
def configure(*, bin: str | os.PathLike | None = ..., tmpdir: ... = ..., cache_dir: ... = ...) -> None
def binary_override() -> Path | None      # configure() beats the env var
def tmpdir() -> Path                      # configure() > env > tempfile.gettempdir()
def cache_dir() -> Path                   # configure() > env > $XDG_CACHE_HOME/cdfviewer > ~/.cache/cdfviewer
def reset() -> None                       # tests
```

### WP-A — `_format.py`, `_command.py`

```python
class Sym(str): ...            # a Julia symbol
class Raw(str): ...            # verbatim Julia text
def sym(name: str) -> Sym
def raw(text: str) -> Raw
def format_value(value: object) -> str          # Q3 table; TypeError for range/slice/unknown
def format_kwargs(kwargs: Mapping[str, object]) -> str     # 'a=1, b="x"'
def format_dims(dims: Mapping[str, int]) -> str            # 'z=0,time=3'
def format_save_options(*, filename: str | None, framerate: int | None,
                        px_per_unit: int | None, frames: tuple | None,
                        overwrite: bool | None) -> str     # only what is set; frames → range=a:s:b

class Command(list[str]):
    @property
    def shell(self) -> str                      # shlex.join(self)
SELECTION = (var, x, y, z, plot_type, ani_dim, dims, over, over_plot, kwargs,
             grid, theme, no_grid_search, use_local, menu, no_summary)  # keyword-only, all default None/False
def build_args(path: str | os.PathLike | Sequence[str | os.PathLike], *, <SELECTION>,
               savefig: bool = False, record: bool = False,
               filename=None, framerate=None, px_per_unit=None, frames=None,
               overwrite=None) -> list[str]     # argv without the binary; paths absolute
def command(path, *, <SELECTION>, savefig=False, record=False, <save options>) -> Command
    # [str(_binary.resolve()), *build_args(...)]
```

`build_args` emits, in CLI order: files, `-v`, `-x`, `-y`, `-z`, `-p`,
`-a`, `--dims=...`, one `--over X` per entry then one `--over-plot Y` per
entry, `--kwargs=...`, `-g`, `--theme`, flags, `--savefig`/`--record`,
`-s ...`. `filename` is `~`-expanded and made absolute. In-memory `path`
objects are **not** handled here (WP-C does that before calling).

### WP-B — `_binary.py`, `_launcher.py`, `__main__.py`

```python
ASSET = "cdfviewer-linux-x86_64.tar.zst"
def release_url(version: str, name: str) -> str
def candidates_on_path() -> list[Path]        # every `cdfviewer` on PATH that is not a python script
def managed_path(version: str = __version__) -> Path   # cache_dir()/<version>/cdfviewer/bin/cdfviewer
def resolve(*, download: bool = True) -> Path  # D3 order; NotFound → CDFViewerError with the platform message
def installed_version(binary: Path) -> str | None      # runs `<bin> --version`, parses "cdfviewer X"
def check_version(binary: Path) -> None        # warns once per process on mismatch
def install(version: str | None = None, *, force: bool = False) -> Path
def download(url: str, dest: Path, *, sha256: str | None) -> None       # progress on TTY stderr
def extract(tarball: Path, dest: Path) -> None  # tar --zstd -x; clear error without zstd
def which() -> Path | None
def prune() -> list[Path]                      # removes all but the current version
def uninstall(version: str | None = None) -> None
def supported_platform() -> bool               # linux + x86_64
```

`_launcher.main()`: `os.execv(bin, [str(bin), *sys.argv[1:]])`; on a
`CDFViewerError` print its message to stderr and exit 1.
`__main__`: `install [--version V] [--force]`, `which`, `prune`,
`uninstall [--version V]`, `--help`; `T201` allowed there.

### WP-C — `_logs.py`, `_data.py`, `_run.py`

```python
@dataclass(frozen=True)
class Record: level: str; message: str        # level in {"Info", "Warning", "Error", "Debug"}
def strip_progress(text: str) -> str           # remove \r-segments and ANSI sequences
def parse_records(text: str) -> list[Record]   # both single-line and block forms; "└ @ ..." lines dropped
def saved_path(records: Iterable[Record]) -> Path | None   # "Saved figure to X" / "Saved animation to X"
def raise_for_records(records, *, argv=None) -> None       # Error → CDFViewerError; Warning → warnings.warn

def is_in_memory(obj: object) -> bool          # has to_netcdf / to_dataset / is ndarray
class TempDataset:                             # .path: Path, .var: str | None, .cleanup()
def write_temp(obj, *, complex: str = "split", var: str | None = None) -> TempDataset
def prepare(ds: "xr.Dataset", *, complex: str) -> tuple["xr.Dataset", dict[str, str]]  # dtype pass; maps complex names

@dataclass
class RunResult: returncode: int; output: str; records: list[Record]
def run(argv: Sequence[str], *, verbose: bool = False, check: bool = True) -> RunResult
def savefig(path, *, <SELECTION>, filename=None, px_per_unit=None, overwrite=None,
            complex="split", verbose=False) -> Path
def record(path, *, <SELECTION>, filename=None, framerate=None, px_per_unit=None,
           frames=None, overwrite=None, complex="split", verbose=False) -> Path
```

`run` captures stdout+stderr merged; with `verbose` it also streams the
raw text to `sys.stderr` as it arrives. `savefig`/`record`: temp file for
in-memory input (cleaned up after the process exits), `command(...)`,
`run`, `raise_for_records`, return `saved_path` (error if absent).

### WP-D — `_session.py`

```python
class Session:
    def __init__(self, path, *, <SELECTION>, reuse: bool = True, visible: bool = True,
                 verbose: bool = False, complex: str = "split", timeout: float = 120.0)
    # reuse: registry hit → return the existing object (via __new__) and apply the declaration
    def send(self, line: str, *, timeout: float | None = None) -> str   # text between prompts; records checked
    def var(self, name: str) -> None;  def plot(self, plot_type: str) -> None
    def axes(self, *, x=None, y=None, z=None) -> None
    def isel(self, **dims: int) -> None;  def sel(self, **dims: object) -> None
    def over(self, var: str | None, plot_type: str | None = None, *, layer: int = 2) -> None
    def set(self, **kwargs: object) -> None;  def delete(self, *names: str) -> None
    def get(self, name: str) -> str
    def savefig(self, filename=None, *, px_per_unit=None, overwrite=None) -> Path
    def record(self, filename=None, *, framerate=None, px_per_unit=None, frames=None, overwrite=None) -> Path
    def theme(self, name: str) -> None;  def reset(self) -> None
    def export(self) -> str;  def show(self) -> None;  def hide(self) -> None
    def png(self) -> bytes;  def _repr_png_(self) -> bytes
    def apply(self, **declaration) -> None     # the reuse diff; called by __init__ on a hit
    def close(self) -> None;  __enter__/__exit__;  pid: int;  alive: bool
def sessions() -> list[Session];  def close_all() -> None
```

Internals: `Popen(stdin=PIPE, stdout=PIPE, stderr=STDOUT)`; a daemon
reader thread appends to a buffer under a lock and signals a condition
when `CDFViewer> ` is at the end; `send` writes the line, waits for the
next prompt (timeout → `CDFViewerError`), strips progress, parses records,
raises/warns, returns the remaining text. Unsolicited output between
commands is parsed the same way at the next `send`. Registry key:
`(tuple(abs paths) or id(obj), grid, use_local)`; `atexit` closes all.
Declared state is kept as a dict; `apply` sends only the differences in
setup order (var, plot, axes, dims, ani_dim, over, kwargs, theme), `del`
for vanished keywords. `visible=False` sends `hide` after startup.

### WP-E — packaging, CI, Julia side, docs

- Julia: `--version` flag (`cdfviewer <Project.toml version>`, exit 0,
  before any dataset is opened) with a test in `test/test_argparse.jl`
  or `test_julia_main.jl`; keep `[ Info: Saved figure to` /
  `Saved animation to` lines as they are (they are the protocol now —
  a comment in `Output.jl` says so).
- `release.yml`: upload `cdfviewer-linux-x86_64.tar.zst.sha256`; build
  the wheel (`uv build` in `python/`) and publish to PyPI on tags via
  trusted publishing (`pypa/gh-action-pypi-publish`; the PyPI side is set
  up by hand once); replace the shell smoke test with
  `uv run pytest -m binary` against `dist/`; fail if
  `python/src/cdfviewer/_version.py` differs from `Project.toml`.
- `CI.yml`: a `python` job (`conventions.md`): setup-uv, `uv sync --extra
  dev`, `ruff check src tests`, `pytest --cov --cov-report=`, `coverage
  report` (fail_under 95), version drift check. Paths filter.
- `docs/src/usage/python.md` from `api.md`, linked from the manual's
  navigation (`docs/make.jl` pages list); `python/README.md` for PyPI.
- `.pre-commit-config.yaml` at the repo root with the ruff hook scoped to
  `python/`.

## Parallel run

| Package | Files | Depends on (interfaces only) |
|---|---|---|
| WP-A | `_format.py`, `_command.py` + tests | `_config`, `_binary.resolve` |
| WP-B | `_binary.py`, `_launcher.py`, `__main__.py` + tests | `_config`, `_errors` |
| WP-C | `_logs.py`, `_data.py`, `_run.py` + tests | `_command`, `_binary.resolve`, `_errors` |
| WP-D | `_session.py` + tests | `_command`, `_binary.resolve`, `_logs`, `_data` |
| WP-E | Julia `--version`, workflows, docs page, README, pre-commit | the API as specified |

Each agent: implements against the stubs of the others (their tests use
the fake binary and, where a sibling module is needed at runtime, the
scaffold's stub or a monkeypatched stand-in); runs `uv run ruff check src
tests` and `uv run pytest --cov` on its own files; reports coverage of
its modules (target ≥ 95 % each) and any interface change it needs.

## Integration (lead)

Merge the five branches, `uv sync --extra dev`, `ruff check`, full
`pytest --cov` with `fail_under = 95`, `test_init.py` green; then the
`binary` tests and a real-data check (the geostrophic adjustment zarr
through `savefig`, `record` and a `Session`) against a source build
(`julia --project=. -e 'using CDFViewer; exit(julia_main())' -- ...`
wrapped as a `cdfviewer` script on `PATH`), since the installed 2026.8.1
bundle has neither `--version` nor zarr support. Then fold the docs and
delete `design/`.
