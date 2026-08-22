# Conventions — copied from fridom

Source: `/home/silvano/Projects/fridom` (its `pyproject.toml`, `AGENTS.md`,
`.pre-commit-config.yaml`, `.github/workflows/tests.yml`), surveyed
2026-08-22. Items marked **(deviation)** differ from fridom on purpose; all four were
confirmed on 2026-08-22.

## Layout and build

- `python/` holds the package: `python/pyproject.toml`, src layout
  `python/src/cdfviewer/`, tests in `python/tests/` mirroring the source
  tree (`test_<module>.py`, function-based `def test_*`, no test classes),
  a `test_init.py` parametrised over the `__init__` re-exports.
- Build backend setuptools (`setuptools>=61`), `packages.find where=["src"]`.
- `requires-python = ">=3.11"`, ruff `target-version = "py311"` **(deviation
  from the earlier ">=3.10" note; fridom is 3.11)**.
- Version hardcoded in `pyproject.toml`; must equal `Project.toml`'s
  `version`. A CI step compares the two and fails on drift.
- uv drives everything: `uv.lock` committed in `python/`, `uv sync --extra
  dev`, `uv run pytest`, `uv run ruff check`. Optional groups: `xarray`
  (xarray + netCDF4), `dev` (pytest, pytest-cov, coverage, ruff,
  pre-commit, xarray, netCDF4, zarr).
- MIT license (the repo's), `from __future__ import annotations` in every
  source module, PEP 604 unions, no quoted forward refs, annotation-only
  imports under `if TYPE_CHECKING:  # pragma: no cover`.

## Ruff

Verbatim from fridom, minus the fridom-specific per-file entries:

```toml
[tool.ruff]
target-version = "py311"
line-length = 79

[tool.ruff.lint]
select = ["ALL"]
extend-select = ["D203"]
ignore = [
  "D105", "D107", "D211", "D212",
  "FBT001", "FBT002", "PLR0913", "TRY003", "EM101", "EM102",
  "ANN401",
  "TD001", "TD003", "FIX001", "FIX002",
  "COM812",
]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["D100", "D101", "D102", "D103", "S101", "ANN", "INP001",
                   "SLF001", "PLR2004"]
"__init__.py" = ["F401"]

[tool.ruff.lint.pydocstyle]
convention = "numpy"
```

Likely additions for this package (decide as they come up, each with a
comment): `S603`/`S607` where `subprocess` is called with a list we built
ourselves, `T201` in the `__main__` management CLI.

- No formatter (fridom keeps 79-char lines by hand; ruff-format unused).
- Pre-commit: the single `ruff-check --fix` hook.
- **(deviation)** ruff also runs in CI (`uv run ruff check src tests`);
  fridom only has the pre-commit hook.

## Docstrings

NumPy style, `convention = "numpy"`, summary on the second line (D213
behaviour), blank line before class docstrings (D203), `name : type` with
no backticks, `name : type, optional` with `(default: X)` in prose, a
module docstring in every module. fridom's extra `Description` section is
optional here.

## Tests and coverage

```toml
[tool.pytest.ini_options]
addopts = ["--import-mode=importlib", "--strict-markers"]
markers = ["binary: needs a real cdfviewer binary"]
filterwarnings = ["error"]   # narrow `ignore:` entries only with a comment

[tool.coverage.run]
source_pkgs = ["cdfviewer"]
branch = true
relative_files = true

[tool.coverage.paths]
source = ["src/cdfviewer", "**/site-packages/cdfviewer"]

[tool.coverage.report]
fail_under = 95
precision = 1
show_missing = true
skip_covered = true
exclude_also = [
  "if TYPE_CHECKING:",
  "@(abc\\.)?abstractmethod",
  "raise NotImplementedError",
  "if __name__ == .__main__.:",
]
```

- `fail_under = 95` is the gate, measured **without** the real binary
  (unit tests only), so coverage does not depend on a 1 GB download:
  - a **fake binary** fixture — a small Python script installed as
    `cdfviewer` in a temp `PATH` — emulates the CLI (`--version`,
    `--savefig`/`--record` writing a file and printing `Saved figure to`,
    the basic REPL with its `CDFViewer> ` prompt, `Warning:`/`Error:`
    records on demand). `Session`, the runners, error mapping and version
    checks are tested against it;
  - the download is tested against a local `http.server` fixture serving
    a tiny tarball and its `.sha256`;
  - xarray-dependent tests use `pytest.importorskip("xarray")`.
- `@pytest.mark.binary` tests run against the real binary when one
  resolves (conftest `pytest_runtest_setup` skips them otherwise), locally
  and in the release job against the freshly built `dist/` — replacing the
  current shell smoke test.
- **(deviation)** no Codecov (fridom uploads; this repo has no token).
  `coverage report` in CI enforces the threshold; revisit if a badge is
  wanted.

## Type checking

As fridom: fully annotated source enforced by ruff's `ANN*` rules, but no
mypy/pyright and **no `py.typed`** (resolves the Q10 doubt).

## CI

A `python` job in `.github/workflows/CI.yml` (paths filter on `python/**`
and `Project.toml`): `astral-sh/setup-uv`, `uv sync --extra dev`,
`uv run ruff check src tests`, `uv run pytest --cov --cov-report=`,
`uv run coverage report` (fails under 95 %), the version-drift check.
Python 3.11 only for now, `fail-fast: false`.

## Git

As the repo already does: `<type>/<kebab-topic>` branches, `git merge
--no-ff`, no changelog file (release notes live in the tag annotation and
the GitHub release).
