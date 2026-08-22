"""
``python -m cdfviewer``: manage the downloaded bundle.

Work package B (stub). Subcommands: ``install [--version V] [--force]``,
``which``, ``prune``, ``uninstall [--version V]``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Sequence


def main(argv: Sequence[str] | None = None) -> int:
    """Run one management subcommand and return the exit code."""
    raise NotImplementedError


if __name__ == "__main__":
    raise SystemExit(main())
