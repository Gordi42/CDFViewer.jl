"""
What a save hands back: a path that also shows itself in a notebook.

`savefig` returns a `Figure`, `record` an `Animation`. Both wrap the
absolute path the app reported and are path-like, so they can be opened,
copied and printed like the `pathlib.Path` they carry. As the value of a
notebook cell they display: an image for a figure, an embedded player
for a recording, through IPython's ``_repr_mimebundle_`` hook. A file
larger than the `embed_limit` is not embedded and warns instead.
"""

from __future__ import annotations

import base64
import warnings
from pathlib import Path
from typing import TYPE_CHECKING, Final

from ._config import embed_limit
from ._errors import CDFViewerWarning

if TYPE_CHECKING:  # pragma: no cover
    import os
    from collections.abc import Container

#: The mimetype of every format the app writes, plus the common cousins.
MIMETYPES: Final = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mkv": "video/x-matroska",
}
_MEGABYTE: Final = 1024 * 1024


class _Output:

    """
    A file the app wrote, usable as a path and displayable in a notebook.

    The base of `Figure` and `Animation`; it is the subclass that names
    what the file is.

    Parameters
    ----------
    path : str | PathLike
        The file the app reported writing, normally absolute.
    """

    def __init__(self, path: str | os.PathLike[str]) -> None:
        self.path = Path(path)

    def __fspath__(self) -> str:
        return str(self.path)

    def __str__(self) -> str:
        return str(self.path)

    def __repr__(self) -> str:
        return f"{type(self).__name__}({str(self.path)!r})"

    def __eq__(self, other: object) -> bool:
        if type(other) is not type(self):
            return NotImplemented
        return self.path == other.path

    def __hash__(self) -> int:
        return hash((type(self), self.path))

    def read_bytes(self) -> bytes:
        """
        The contents of the file, read now.

        Nothing is cached: a file that was written over is read again.

        Returns
        -------
        bytes
            What is on disk at this moment.
        """
        return self.path.read_bytes()

    @property
    def mimetype(self) -> str | None:
        """The mimetype the suffix stands for, or ``None`` if unknown."""
        return MIMETYPES.get(self.path.suffix.lower())

    def _fits(self) -> bool:
        """Whether the file is small enough to embed; warns when it is not."""
        limit = embed_limit()
        size = self.path.stat().st_size / _MEGABYTE
        if size <= limit:
            return True
        warnings.warn(
            f"{self.path.name} is {size:.1f} MB, more than the "
            f"{limit:g} MB embed limit, so it is not shown inline; raise "
            "the limit with cdfviewer.configure(embed_limit=...)",
            CDFViewerWarning,
            stacklevel=2,
        )
        return False

    def _embedded(self) -> dict[str, object]:
        """The file itself, as the one mimetype a notebook should render."""
        mimetype = self.mimetype
        if mimetype is None or not self._fits():
            return {}
        if mimetype.startswith("image/"):
            return {mimetype: self.read_bytes()}
        # a video is embedded the way IPython.display.Video(embed=True)
        # does it; `muted` is what lets a browser autoplay at all
        data = base64.b64encode(self.read_bytes()).decode("ascii")
        return {
            "text/html": (
                "<video controls autoplay loop muted "
                f'src="data:{mimetype};base64,{data}"></video>'
            )
        }

    def _repr_mimebundle_(
        self,
        include: Container[str] | None = None,
        exclude: Container[str] | None = None,
    ) -> dict[str, object]:
        """
        What IPython should display for this file (its rich-display hook).

        Always carries ``text/plain``; a figure adds its image bytes and
        a recording an HTML player with the video embedded.

        Parameters
        ----------
        include : Container[str], optional
            Keep only these mimetypes (default: keep all).
        exclude : Container[str], optional
            Drop these mimetypes (default: drop none).

        Returns
        -------
        dict[str, object]
            The mimetype bundle, as IPython expects it.
        """
        bundle: dict[str, object] = {"text/plain": repr(self)}
        bundle.update(self._embedded())
        if include is not None:
            bundle = {
                key: value for key, value in bundle.items() if key in include
            }
        if exclude is not None:
            bundle = {
                key: value
                for key, value in bundle.items()
                if key not in exclude
            }
        return bundle


class Figure(_Output):

    """
    A figure file `savefig` wrote: a path that displays as an image.

    Parameters
    ----------
    path : str | PathLike
        The image file the app reported writing.
    """


class Animation(_Output):

    """
    A video file `record` wrote: a path that displays as a player.

    Parameters
    ----------
    path : str | PathLike
        The video file the app reported writing.
    """
