"""The fake binary behaves the way the rest of the tests rely on."""

import os
import select
import shutil
import subprocess
import time

import pytest

PROMPT = b"CDFViewer> "


def read_until_prompt(proc, timeout=10.0) -> bytes:
    fd = proc.stdout.fileno()
    buf = b""
    deadline = time.monotonic() + timeout
    while not buf.endswith(PROMPT):
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            buf += chunk
        assert time.monotonic() < deadline, buf
    return buf[: -len(PROMPT)]


def test_fake_binary_is_found_on_path(fake_binary):
    assert shutil.which("cdfviewer") == str(fake_binary)


def test_version(fake_binary, fake_config):
    fake_config(version="1.2.3")
    result = subprocess.run(
        [fake_binary, "--version"], capture_output=True, text=True, check=True
    )
    assert result.stdout == "cdfviewer 1.2.3\n"


def test_missing_file_is_an_error(fake_binary, tmp_path):
    result = subprocess.run(
        [fake_binary, str(tmp_path / "nope.nc"), "--savefig"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert "File or directory not found" in result.stdout


def test_savefig_writes_the_file_and_says_where(
    fake_binary, data_file, tmp_path
):
    target = tmp_path / "out" / "fig.png"
    target.parent.mkdir()
    argv = [fake_binary, str(data_file), "-v", "t", "--savefig"]
    argv += ["-s", f'filename="{target}"']
    result = subprocess.run(argv, capture_output=True, text=True, check=True)
    assert target.exists()
    assert f"[ Info: Saved figure to {target}" in result.stdout


def test_record_prints_a_progress_bar(fake_binary, data_file, tmp_path):
    target = tmp_path / "movie.mp4"
    argv = [fake_binary, str(data_file), "--record"]
    argv += [f'--saveoptions=filename="{target}"']
    # bytes, not text: text mode would turn the bar's \r into newlines
    result = subprocess.run(argv, capture_output=True, check=True)
    output = result.stdout.decode()
    assert target.read_bytes() == b"fake-mp4"
    assert "\rRecording 100%" in output
    assert f"Saved animation to {target}" in output


def test_configured_failure(fake_binary, fake_config, data_file):
    fake_config(fail_save=True, records=["[ Info: extra"])
    result = subprocess.run(
        [fake_binary, str(data_file), "--savefig"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert "[ Info: extra" in result.stdout
    assert "┌ Error: Saving failed" in result.stdout


def test_repl_protocol(fake_binary, data_file, tmp_path):
    argv = [fake_binary, str(data_file), "-v", "t"]
    argv += ["--kwargs=colormap=:viridis"]
    with subprocess.Popen(
        argv,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ) as proc:
        startup = read_until_prompt(proc)
        assert b"Type 'help'" in startup

        def send(line: str) -> str:
            proc.stdin.write(line.encode() + b"\n")
            proc.stdin.flush()
            return read_until_prompt(proc).decode()

        assert send("get colormap") == "[ Info: colormap => :viridis\n"
        assert send("get levels") == "[ Info: levels => :balance\n"
        assert '└ xunit => "km"' in send('xunit="km"')
        assert "┌ Warning: Unknown command: bogus" in send("bogus")
        assert "┌ Error: xunit must be" in send("fail")
        assert "Invalid selection" in send("v does_not_exist")
        assert send("isel time 3") == "[ Info: isel time 3\n"
        png = tmp_path / "s.png"
        assert f"Saved figure to {png}" in send(f'savefig filename="{png}"')
        assert png.exists()
        exported = send("export")
        assert "--kwargs='colormap=:viridis, xunit=\"km\"'" in exported
        assert "Closed figure window" in send("hide")
        proc.stdin.close()
        assert proc.wait(timeout=10) == 0
        assert b"Exiting CDFViewer REPL" in proc.stdout.read()


@pytest.mark.parametrize(("line", "code"), [("crash", 3), ("exit", 0)])
def test_repl_ends_on_command(fake_binary, data_file, line, code):
    with subprocess.Popen(
        [fake_binary, str(data_file)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ) as proc:
        read_until_prompt(proc)
        proc.stdin.write(line.encode() + b"\n")
        proc.stdin.flush()
        assert proc.wait(timeout=10) == code
        proc.stdin.close()
        proc.stdout.read()
