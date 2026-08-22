"""
Python interface to CDFViewer, the interactive NetCDF and zarr viewer.

`savefig` and `record` render one figure or animation per call,
`command` builds the command line without running it, and `Session`
keeps a viewer open and drives it from a script or a notebook. See the
manual's "Python" page.
"""

from __future__ import annotations

from ._command import Command, command
from ._config import configure
from ._errors import CDFViewerError, CDFViewerWarning
from ._format import Raw, Sym, raw, sym
from ._run import record, run, savefig
from ._session import Session, close_all, sessions
from ._version import __version__

__all__ = [
    "CDFViewerError",
    "CDFViewerWarning",
    "Command",
    "Raw",
    "Session",
    "Sym",
    "__version__",
    "close_all",
    "command",
    "configure",
    "raw",
    "record",
    "run",
    "savefig",
    "sessions",
    "sym",
]
