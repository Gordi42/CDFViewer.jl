"""
The ``cdfviewer`` console script: resolve the binary and become it.

`os.execv` replaces this process, so the terminal, stdin, Ctrl-C and the
exit code belong to the app itself and the interactive REPL behaves
exactly as the native binary does. The arguments are passed on
untouched; the management commands live in `cdfviewer.__main__`.
"""

from __future__ import annotations

import os
import sys
from typing import NoReturn

from . import _binary
from ._errors import CDFViewerError


def main() -> NoReturn:
    """Replace this process with the binary, arguments untouched."""
    try:
        binary = _binary.resolve()
    except CDFViewerError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)
    os.execv(str(binary), [str(binary), *sys.argv[1:]])  # noqa: S606
