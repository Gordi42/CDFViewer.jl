"""What a save hands back: `Figure` and `Animation`."""

import base64
import os
import shutil
from pathlib import Path

import pytest

from cdfviewer import _config
from cdfviewer._errors import CDFViewerWarning
from cdfviewer._output import Animation, Figure

PNG = b"\x89PNG\r\n\x1a\n" + bytes(16)
MP4 = b"fake-mp4"


@pytest.fixture
def figure(tmp_path) -> Figure:
    path = tmp_path / "fig.png"
    path.write_bytes(PNG)
    return Figure(path)


@pytest.fixture
def animation(tmp_path) -> Animation:
    path = tmp_path / "movie.mp4"
    path.write_bytes(MP4)
    return Animation(path)


# ------------------------------------------------------------ the path ----


def test_the_path_is_kept_as_a_path(tmp_path):
    assert Figure(str(tmp_path / "fig.png")).path == tmp_path / "fig.png"
    assert Animation(tmp_path / "a.mp4").path == tmp_path / "a.mp4"


def test_it_is_path_like(figure, tmp_path):
    assert os.fspath(figure) == str(figure.path)
    assert Path(figure) == figure.path
    with Path(figure).open("rb") as handle:
        assert handle.read() == PNG
    copy = shutil.copy(figure, tmp_path / "copy.png")
    assert Path(copy).read_bytes() == PNG


def test_str_is_the_path_and_repr_names_the_class(figure, animation):
    assert str(figure) == str(figure.path)
    assert repr(figure) == f"Figure('{figure.path}')"
    assert repr(animation) == f"Animation('{animation.path}')"


def test_equality_and_hash_go_by_class_and_path(tmp_path):
    path = tmp_path / "fig.png"
    assert Figure(path) == Figure(path)
    assert Figure(path) != Figure(tmp_path / "other.png")
    assert Figure(path) != Animation(path)
    assert Figure(path) != path  # a bare path is not a result
    assert hash(Figure(path)) == hash(Figure(path))
    assert hash(Figure(path)) != hash(Animation(path))
    assert len({Figure(path), Figure(path), Animation(path)}) == 2


def test_read_bytes_reads_the_file_again_every_time(figure):
    assert figure.read_bytes() == PNG
    figure.path.write_bytes(b"written over")
    assert figure.read_bytes() == b"written over"


@pytest.mark.parametrize(
    ("name", "mimetype"),
    [
        ("fig.png", "image/png"),
        ("fig.PNG", "image/png"),
        ("fig.jpg", "image/jpeg"),
        ("fig.jpeg", "image/jpeg"),
        ("a.gif", "image/gif"),
        ("a.mp4", "video/mp4"),
        ("a.webm", "video/webm"),
        ("a.mkv", "video/x-matroska"),
        ("a.txt", None),
        ("a", None),
    ],
)
def test_the_mimetype_comes_from_the_suffix(name, mimetype, tmp_path):
    assert Figure(tmp_path / name).mimetype == mimetype


# ---------------------------------------------------------- the bundle ----


def test_a_figure_carries_its_image_bytes(figure):
    bundle = figure._repr_mimebundle_()
    assert bundle["text/plain"] == repr(figure)
    assert bundle["image/png"] == PNG
    assert set(bundle) == {"text/plain", "image/png"}


def test_an_image_recording_is_an_image_too(tmp_path):
    path = tmp_path / "movie.gif"
    path.write_bytes(b"GIF89a")
    bundle = Animation(path)._repr_mimebundle_()
    assert bundle["image/gif"] == b"GIF89a"


def test_a_recording_carries_an_embedded_player(animation):
    bundle = animation._repr_mimebundle_()
    assert set(bundle) == {"text/plain", "text/html"}
    html = bundle["text/html"]
    data = base64.b64encode(MP4).decode("ascii")
    assert html == (
        "<video controls autoplay loop muted "
        f'src="data:video/mp4;base64,{data}"></video>'
    )


def test_the_player_names_the_files_own_mimetype(tmp_path):
    path = tmp_path / "movie.mkv"
    path.write_bytes(MP4)
    html = Animation(path)._repr_mimebundle_()["text/html"]
    assert "data:video/x-matroska;base64," in html


def test_an_unknown_suffix_is_only_text(tmp_path):
    path = tmp_path / "something.dat"
    path.write_bytes(b"whatever")
    assert Figure(path)._repr_mimebundle_() == {
        "text/plain": repr(Figure(path))
    }


def test_include_keeps_only_what_it_names(figure):
    assert set(figure._repr_mimebundle_(include={"image/png"})) == {
        "image/png"
    }
    assert figure._repr_mimebundle_(include={"application/json"}) == {}


def test_exclude_drops_what_it_names(figure):
    assert set(figure._repr_mimebundle_(exclude={"image/png"})) == {
        "text/plain"
    }


def test_include_and_exclude_together(figure):
    bundle = figure._repr_mimebundle_(
        include={"text/plain", "image/png"}, exclude={"text/plain"}
    )
    assert set(bundle) == {"image/png"}


# ----------------------------------------------------- the embed limit ----


def test_a_file_over_the_limit_warns_and_is_not_embedded(animation):
    _config.configure(embed_limit=1e-6)  # about one byte
    with pytest.warns(CDFViewerWarning, match="embed limit") as record:
        bundle = animation._repr_mimebundle_()
    assert bundle == {"text/plain": repr(animation)}
    message = str(record[0].message)
    assert "movie.mp4" in message
    assert "cdfviewer.configure(embed_limit=...)" in message


def test_the_limit_applies_to_images_as_well(figure):
    _config.configure(embed_limit=1e-6)
    with pytest.warns(CDFViewerWarning, match="embed limit"):
        assert figure._repr_mimebundle_() == {"text/plain": repr(figure)}


def test_a_raised_limit_embeds_again(animation):
    _config.configure(embed_limit=1e-6)
    with pytest.warns(CDFViewerWarning):
        animation._repr_mimebundle_()
    _config.configure(embed_limit=100.0)
    assert "text/html" in animation._repr_mimebundle_()
