#!/usr/bin/env bash
# Manage a live CDFViewer session driven through a FIFO.
#
#   session.sh start <file.nc> [extra CLI args...]  # launch (~20 s until ready)
#   session.sh send "<command>" ["<command>" ...]   # queue REPL command(s)
#   session.sh save <abs-path.png> [timeout_s]      # savefig and wait for the file
#   session.sh record <abs-path.mp4|gif> [opts]     # record animation, wait for file
#   session.sh log [n]                              # tail the session log (default 30)
#   session.sh status                               # running / not running
#   session.sh stop                                 # graceful exit (falls back to kill)
#
# Notes:
# - stdout in the log is buffered by Julia and appears late; stderr
#   ("[ Info: ..." lines) is live. Never wait on stdout markers; the save/
#   record subcommands wait on the output file instead.
# - One session at a time. The figure window becomes visible on the user's
#   display as soon as a plot type is selected.
set -u

SDIR="${CDFVIEW_SESSION_DIR:-/tmp/cdfview-session-$USER}"
FIFO="$SDIR/cmd.fifo"
LOG="$SDIR/session.log"

# Resolve how to launch CDFViewer: prefer the compiled `cdfviewer`
# executable (~2 s startup), fall back to running from a checkout of the
# repository (~15 s startup).
find_repo() {
    local c
    for c in "${CDFVIEWER_REPO:-}" "${CLAUDE_PROJECT_DIR:-}" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." 2>/dev/null && pwd)" \
             "$HOME/Projects/CDFViewer.jl"; do
        [ -n "$c" ] && [ -f "$c/src/CDFViewer.jl" ] && { echo "$c"; return 0; }
    done
    return 1
}
if command -v cdfviewer >/dev/null 2>&1; then
    LAUNCH=(cdfviewer)
elif REPO=$(find_repo); then
    LAUNCH=(julia --project="$REPO" -e 'using CDFViewer; julia_main()')
else
    echo "ERROR: neither 'cdfviewer' on PATH nor a CDFViewer.jl checkout found" >&2
    echo "       (set CDFVIEWER_REPO=/path/to/CDFViewer.jl)" >&2
    exit 1
fi

app_pid() { cat "$SDIR/app.pid" 2>/dev/null; }
running() { [ -n "$(app_pid)" ] && kill -0 "$(app_pid)" 2>/dev/null; }

cmd_start() {
    [ $# -ge 1 ] || { echo "usage: session.sh start <file.nc> [args...]"; exit 1; }
    if running; then echo "ERROR: session already running (PID $(app_pid)); use send/stop"; exit 1; fi
    rm -rf "$SDIR"; mkdir -p "$SDIR"; mkfifo "$FIFO"
    # Holder keeps the FIFO open so the app never sees EOF between sends
    sleep 86400 > "$FIFO" &
    echo $! > "$SDIR/holder.pid"
    "${LAUNCH[@]}" "$@" > "$LOG" 2>&1 < "$FIFO" &
    echo $! > "$SDIR/app.pid"
    # Readiness: [ Info: lines are stderr (unbuffered). Wait for "Setup" then a grace period.
    for i in $(seq 1 90); do grep -q "Setup" "$LOG" 2>/dev/null && break; sleep 1; done
    sleep 5
    if running; then echo "READY (PID $(app_pid), log: $LOG)"; else
        echo "FAILED to start:"; tail -20 "$LOG"; exit 1; fi
}

cmd_send() {
    running || { echo "ERROR: no session running"; exit 1; }
    for c in "$@"; do echo "$c" > "$FIFO"; done
    echo "sent: $#  command(s)"
}

wait_for_file() { # path timeout
    local path=$1 timeout=${2:-60}
    for i in $(seq 1 "$timeout"); do
        [ -s "$path" ] && { sleep 1; echo "OK: $path ($(du -h "$path" | cut -f1))"; return 0; }
        running || { echo "ERROR: session died"; tail -10 "$LOG"; return 1; }
        sleep 1
    done
    echo "TIMEOUT: $path not created after ${timeout}s"; return 1
}

cmd_save() {
    [ $# -ge 1 ] || { echo "usage: session.sh save <abs-path.png> [timeout]"; exit 1; }
    running || { echo "ERROR: no session running"; exit 1; }
    rm -f "$1"
    echo "savefig filename=$1" > "$FIFO"
    wait_for_file "$1" "${2:-60}"
}

cmd_record() {
    [ $# -ge 1 ] || { echo "usage: session.sh record <abs-path.mp4> [\"framerate=24\"] [timeout]"; exit 1; }
    running || { echo "ERROR: no session running"; exit 1; }
    local path=$1 opts=${2:-framerate=24} timeout=${3:-240}
    rm -f "$path"
    echo "record filename=$path, $opts" > "$FIFO"
    wait_for_file "$path" "$timeout"
}

cmd_log() { tail -"${1:-30}" "$LOG" 2>/dev/null || echo "(no log)"; }

cmd_status() { running && echo "running (PID $(app_pid))" || echo "not running"; }

cmd_stop() {
    if running; then
        echo "exit" > "$FIFO"
        for i in $(seq 1 15); do running || break; sleep 1; done
    fi
    running && { echo "forcing kill"; kill "$(app_pid)" 2>/dev/null; }
    kill "$(cat "$SDIR/holder.pid" 2>/dev/null)" 2>/dev/null
    rm -rf "$SDIR"
    echo "stopped"
}

case "${1:-}" in
    start)  shift; cmd_start "$@";;
    send)   shift; cmd_send "$@";;
    save)   shift; cmd_save "$@";;
    record) shift; cmd_record "$@";;
    log)    shift; cmd_log "$@";;
    status) cmd_status;;
    stop)   cmd_stop;;
    *) echo "usage: session.sh {start|send|save|record|log|status|stop}"; exit 1;;
esac
