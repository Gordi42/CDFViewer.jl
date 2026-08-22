"""
``python -m cdfviewer``: manage the downloaded bundle.

Subcommands: ``install [--version V] [--force]``, ``which``, ``prune``,
``uninstall [--version V]``. They live here and not under the
``cdfviewer`` launcher, which stays a pure passthrough to the app.
"""

from __future__ import annotations

import argparse
import sys
from typing import TYPE_CHECKING

from . import _binary
from ._errors import CDFViewerError
from ._version import __version__

if TYPE_CHECKING:  # pragma: no cover
    from collections.abc import Sequence


def _parser() -> argparse.ArgumentParser:
    """The command line of ``python -m cdfviewer``."""
    parser = argparse.ArgumentParser(
        prog="python -m cdfviewer",
        description="Manage the cdfviewer bundle this package uses.",
    )
    parser.add_argument(
        "--version", action="version", version=f"cdfviewer {__version__}"
    )
    commands = parser.add_subparsers(dest="command", required=True)

    install = commands.add_parser(
        "install", help="download and unpack the bundle"
    )
    install.add_argument(
        "--version",
        dest="bundle_version",
        default=None,
        help=f"the release to install (default: {__version__})",
    )
    install.add_argument(
        "--force",
        action="store_true",
        help="download again even when the bundle is already there",
    )

    commands.add_parser("which", help="print the binary that would be run")
    commands.add_parser("prune", help="delete all but the current bundle")

    uninstall = commands.add_parser(
        "uninstall", help="delete one managed bundle"
    )
    uninstall.add_argument(
        "--version",
        dest="bundle_version",
        default=None,
        help=f"the release to remove (default: {__version__})",
    )
    return parser


def _install(args: argparse.Namespace) -> int:
    """Install a bundle and print where it went."""
    print(_binary.install(args.bundle_version, force=args.force))
    return 0


def _which() -> int:
    """Print the binary that would be run, if there is one."""
    binary = _binary.which()
    if binary is None:
        print("no cdfviewer binary found", file=sys.stderr)
        return 1
    print(binary)
    return 0


def _prune() -> int:
    """Delete the bundles of other versions and say which."""
    removed = _binary.prune()
    if not removed:
        print("nothing to remove")
    for path in removed:
        print(f"removed {path}")
    return 0


def _uninstall(args: argparse.Namespace) -> int:
    """Delete one bundle."""
    version = args.bundle_version or __version__
    _binary.uninstall(version)
    print(f"removed the bundle of cdfviewer {version}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """
    Run one management subcommand and return the exit code.

    Parameters
    ----------
    argv : Sequence[str] or None, optional
        The arguments to parse (default: None, ``sys.argv[1:]``).

    Returns
    -------
    int
        0 on success, 1 when the command failed or found nothing.
    """
    args = _parser().parse_args(argv)
    try:
        if args.command == "install":
            return _install(args)
        if args.command == "which":
            return _which()
        if args.command == "prune":
            return _prune()
        return _uninstall(args)
    except CDFViewerError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
