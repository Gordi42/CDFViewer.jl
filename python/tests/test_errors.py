import warnings

import pytest

from cdfviewer import CDFViewerError, CDFViewerWarning


def test_message_alone_when_there_is_no_output():
    err = CDFViewerError("it broke")
    assert str(err) == "it broke"
    assert err.returncode is None
    assert err.argv is None
    assert err.output == ""


def test_message_ends_with_the_output_tail():
    output = "\n".join(f"line {i}" for i in range(30)) + "\n\n"
    err = CDFViewerError(
        "exit 1", returncode=1, argv=("cdfviewer", "f.nc"), output=output
    )
    text = str(err)
    assert text.startswith("exit 1\nOutput of cdfviewer (last lines):\n")
    assert "line 29" in text
    assert "line 9" not in text
    assert err.returncode == 1
    assert err.argv == ["cdfviewer", "f.nc"]
    assert err.output == output


def test_blank_output_lines_are_not_counted():
    err = CDFViewerError("x", output="\n   \n")
    assert str(err) == "x"


def test_warning_is_a_user_warning():
    assert issubclass(CDFViewerWarning, UserWarning)
    with pytest.warns(CDFViewerWarning, match="careful"):
        warnings.warn("careful", CDFViewerWarning, stacklevel=1)
