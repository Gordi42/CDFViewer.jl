"""
A stand-in for the cdfviewer binary, for the tests.

It answers the way the real app was observed to (see
``design/python/workplan.md``, "Spike results"): ``--version`` prints
``cdfviewer <version>``; ``--savefig``/``--record`` write a file named in
``-s`` and print ``[ Info: Saved figure to <path>``; otherwise it runs the
basic REPL with its ``CDFViewer> `` prompt. Every print is flushed.

Behaviour is tuned through a JSON file named by ``CDFVIEWER_FAKE_CONFIG``:
``version``, ``exit_code`` (of a one-shot run), ``records`` (extra lines
printed after startup), ``fail_save`` (a save prints an Error and exits
1), ``startup_delay`` (seconds).
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

DEFAULT_VERSION = "0.0.0"
PNG = b"\x89PNG\r\n\x1a\n" + bytes(16)
VALUE_OPTIONS = {
    "-v": "var",
    "--var": "var",
    "-x": "x",
    "--x-axis": "x",
    "-y": "y",
    "--y-axis": "y",
    "-z": "z",
    "--z-axis": "z",
    "-p": "plot_type",
    "--plot_type": "plot_type",
    "-a": "ani_dim",
    "--ani-dim": "ani_dim",
    "-g": "grid",
    "--grid": "grid",
    "--theme": "theme",
    "--kwargs": "kwargs",
    "--dims": "dims",
    "-s": "saveoptions",
    "--saveoptions": "saveoptions",
}
LIST_OPTIONS = {"--over": "over", "--over-plot": "over_plot"}
FLAGS = {
    "--savefig": "savefig",
    "--record": "record",
    "--menu": "menu",
    "--use-local": "use_local",
    "--no-grid-search": "no_grid_search",
    "--no-summary": "no_summary",
}
SELECTION_COMMANDS = {
    "v", "p", "x", "y", "z", "isel", "sel", "theme", "reset", "pdim",
    "play", "speed", "refresh",
}


def load_config() -> dict:
    path = os.environ.get("CDFVIEWER_FAKE_CONFIG")
    return json.loads(Path(path).read_text()) if path else {}


def out(text: str) -> None:
    print(text, flush=True)


def warning(message: str) -> None:
    out(f"┌ Warning: {message}")
    out("└ @ CDFViewer.ViewerREPL /x/CDFViewer.jl/src/ViewerREPL.jl:1")


def error(message: str) -> None:
    out(f"┌ Error: {message}")
    out("└ @ CDFViewer.Plotting /x/CDFViewer.jl/src/Plotting.jl:1")


def parse_argv(argv: list[str]) -> dict:
    args: dict = {
        "files": [], "over": [], "over_plot": [], "kwargs": "",
        "dims": "", "saveoptions": "",
    }
    for flag in FLAGS.values():
        args[flag] = False
    i = 0
    while i < len(argv):
        token = argv[i]
        name, eq, inline = token.partition("=")
        if name in FLAGS:
            args[FLAGS[name]] = True
        elif name in VALUE_OPTIONS:
            value = inline if eq else argv[i + 1]
            i += 0 if eq else 1
            args[VALUE_OPTIONS[name]] = value
        elif name in LIST_OPTIONS:
            value = inline if eq else argv[i + 1]
            i += 0 if eq else 1
            args[LIST_OPTIONS[name]].append(value)
        else:
            args["files"].append(token)
        i += 1
    return args


def split_pairs(line: str) -> list[str]:
    """Split a keyword line on the commas outside brackets and quotes."""
    pairs, current, depth, quote = [], "", 0, ""
    for char in line:
        if quote:
            quote = "" if char == quote else quote
        elif char in "\"'":
            quote = char
        elif char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        elif char == "," and depth == 0:
            pairs.append(current)
            current = ""
            continue
        current += char
    pairs.append(current)
    return [p.strip() for p in pairs if p.strip()]


def store_pairs(store: dict, line: str) -> None:
    for pair in split_pairs(line):
        key, _, value = pair.partition("=")
        store[key.strip()] = value.strip()


def settings_block(store: dict) -> None:
    if not store:
        out("[ Info: No keyword arguments set.")
        return
    items = [f"{k} => {v}" for k, v in store.items()]
    out("┌ Info: Current plot settings:")
    for item in items[:-1]:
        out(f"│ {item}")
    out(f"└ {items[-1]}")


def save_option(settings: str, key: str) -> str | None:
    match = re.search(rf'{key}=(?:"([^"]*)"|([^,]+))', settings)
    if match is None:
        return None
    return match.group(1) if match.group(1) is not None else match.group(2)


def do_save(cfg: dict, settings: str, *, record: bool) -> int:
    default = "cdfviewer.mp4" if record else "cdfviewer.png"
    path = Path(save_option(settings, "filename") or default)
    path = path.expanduser().resolve()
    if cfg.get("fail_save"):
        error("Saving failed (fake)")
        return 1
    if record:
        sys.stdout.write(
            "\rRecording  50%|█████     |  ETA: 0:00:01\x1b[K"
            "\rRecording 100%|██████████| Time: 0:00:00\x1b[K\n"
        )
        sys.stdout.flush()
        out("[ Info: Finished recording. Saving ...")
        path.write_bytes(b"fake-mp4")
        out(f"[ Info: Saved animation to {path}")
    else:
        path.write_bytes(PNG)
        out(f"[ Info: Saved figure to {path}")
    return 0


def repl(args: dict, cfg: dict) -> int:
    store: dict = {}
    if args["kwargs"]:
        store_pairs(store, args["kwargs"])
    while True:
        sys.stdout.write("CDFViewer> ")
        sys.stdout.flush()
        raw = sys.stdin.readline()
        if not raw:
            out("[ Info: Exiting CDFViewer REPL.")
            return 0
        line = raw.strip()
        if not line:
            continue
        cmd, _, rest = line.partition(" ")
        rest = rest.strip()
        if cmd in {"exit", "quit", "q"}:
            out("[ Info: Exiting CDFViewer REPL.")
            return 0
        if cmd == "get":
            out(f"[ Info: {rest} => {store.get(rest, ':balance')}")
        elif cmd == "del":
            for key in rest.replace(",", " ").split():
                store.pop(key, None)
            settings_block(store)
        elif cmd in SELECTION_COMMANDS or cmd.startswith("over"):
            if rest == "does_not_exist":
                warning(f"Invalid selection: {rest}")
                out("┌ Info: Available options: ")
                out("└ temperature, humidity, u, v")
            else:
                out(f"[ Info: {line}")
        elif cmd == "savefig":
            do_save(cfg, rest, record=False)
        elif cmd == "record":
            do_save(cfg, rest, record=True)
        elif cmd == "export":
            kwargs = ", ".join(f"{k}={v}" for k, v in store.items())
            out("┌ Info: Commandline Arguments:")
            out(f"└ -v{args.get('var', '')} --kwargs='{kwargs}'")
        elif cmd == "conf":
            settings_block(store)
        elif cmd == "hide":
            out("[ Info: Closed figure window.")
        elif cmd == "show":
            out("[ Info: Opened figure window.")
        elif cmd == "fail":
            warning(
                "An error occurred while applying keyword arguments, "
                "reverting: xunit"
            )
            error('xunit must be one of (mm, cm, m, km), got "furlong"')
        elif cmd == "warn":
            warning(rest or "Something to know (fake)")
        elif cmd == "slow":
            time.sleep(float(rest or 1))
            out("[ Info: slept")
        elif cmd == "crash":
            return 3
        elif "=" in line:
            store_pairs(store, line)
            settings_block(store)
        else:
            warning(
                f"Unknown command: {cmd}. Type 'help' for a list of "
                "commands."
            )


def main(argv: list[str]) -> int:
    cfg = load_config()
    version = cfg.get("version", DEFAULT_VERSION)
    if "--version" in argv:
        out(f"cdfviewer {version}")
        return 0
    args = parse_argv(argv)
    time.sleep(cfg.get("startup_delay", 0))
    out(f"[ Info: CDFViewer: {version}  - fake")
    out(f"[ Info: Loading dataset from file(s): {json.dumps(args['files'])}")
    for file in args["files"]:
        if "://" not in file and not Path(file).exists():
            out(f"File or directory not found: {file}")
            return 1
    for line in cfg.get("records", []):
        out(line)
    if args["savefig"] or args["record"]:
        code = do_save(cfg, args["saveoptions"], record=args["record"])
        return code or int(cfg.get("exit_code", 0))
    out("[ Info: Setup...")
    out("[ Info: Ready.")
    out("Type 'help' for a list of commands. Press TAB to complete.")
    return repl(args, cfg)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
