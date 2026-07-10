---
name: cdfplot
description: Plot, animate, or interactively explore NetCDF files (.nc, .cdf) with CDFViewer.jl. Use whenever the user asks to plot/visualize/animate NetCDF data, wants a quick look at a dataset, or wants a plot window opened to navigate themselves.
argument-hint: "<file.nc> [variable] [plot_type] [what you want]"
allowed-tools: ["Bash", "Read", "Write"]
---

# CDFViewer quick plots

User input: `$ARGUMENTS`

CDFViewer.jl is an interactive NetCDF viewer. Three modes — pick the
lightest that fits:

| Situation | Mode |
|:--|:--|
| one question, one image/video | **One-shot** |
| several plots or iterating on one | **Persistent session** |
| user wants to look around themselves | **Interactive handoff** (visible window) |

**Launcher** — define `CDF` once and use it everywhere below:

- `CDF="cdfviewer"` if the compiled executable is on PATH (~2 s startup) —
  check with `command -v cdfviewer`;
- otherwise `CDF="julia --project=$REPO -e 'using CDFViewer; julia_main()'"`
  where `$REPO` is a CDFViewer.jl checkout (`$CLAUDE_PROJECT_DIR` when
  working in the repo, or `$CDFVIEWER_REPO`); ~15 s startup.

Write outputs to a scratch directory, always with absolute paths.

## Inspect a file first

If variables/dimensions are unknown, the startup overview lists them all:

```bash
printf 'exit\n' | $CDF FILE.nc
```

## One-shot plot (PNG)

```bash
$CDF FILE.nc \
  -v VAR -x XDIM -y YDIM -p heatmap --dims="time=5" \
  --savefig -s 'filename="/abs/path/plot.png", px_per_unit=2'
```

- 1 axis → `-p line`; 2 axes → `-p heatmap|contourf|surface`; 3 axes (add
  `-z`) → `-p volume|contour3d`. Maps: add `--kwargs='geographic=true'`
  (lon/lat axes only; add `xticklabelsvisible=false`, they bunch up).
- **Always Read the produced PNG yourself** to check it looks right (axes,
  range, not empty) before presenting it. Fix and rerun if not.

## One-shot animation (MP4/GIF)

```bash
$CDF FILE.nc \
  -v VAR -x XDIM -y YDIM -p heatmap -a time \
  --record -s 'filename="/abs/path/anim.mp4", framerate=24'
```

Format follows the extension (`.mp4 .mkv .webm .gif`). Pin
`--kwargs='colorrange=(lo,hi)'` so frames share one color scale. Verify by
extracting a frame: `ffmpeg -i anim.mp4 -vf "select=eq(n\,10)" -vframes 1 f.png`
and Read it.

## Persistent session / Interactive handoff

Managed by [scripts/session.sh](scripts/session.sh) (FIFO-driven live app;
it resolves the launcher automatically):

```bash
scripts/session.sh start FILE.nc          # one session at a time
scripts/session.sh send "v temperature" "x lon" "y lat" "p heatmap"
scripts/session.sh save /abs/path/plot.png    # waits for the file; Read it
scripts/session.sh send "colormap=:thermal, title=\"...\""   # instant tweaks
scripts/session.sh record /abs/path/anim.mp4 "framerate=24"  # needs prior "pdim time"
scripts/session.sh stop                   # ALWAYS stop when done
```

The figure window becomes **visible on the user's display** the moment a plot
type is selected — that *is* the interactive handoff. When handing over:

- Tell the user the window is open and how to navigate: hover = value
  tooltip; scroll = zoom; right-drag = pan; left-drag = box zoom;
  Ctrl+click = reset; 3D: left-drag rotates.
- `send "menu"` opens the GUI menu window (variable/axes/sliders/buttons).
- Keep the session alive while they explore; apply requests via `send`.
- `send "export"` writes a command-line reproduce-string to the log
  (`session.sh log` — stderr lines are live, stdout lines lag; never wait on
  the log, wait on files).
- If the user clicked Save/Export in the menu, results also appear in the
  log / working directory.

## Command cheat sheet (REPL = `send` strings)

`v var` `x|y|z dim` `p type` · `isel dim i` `sel dim value` ·
`play [dim]` `pdim dim` `speed s` · `key=value, ...` kwargs (colormap,
colorrange, title, levels, labels, limits, figsize, geographic, proj, ...) ·
`get k` `del k` `conf` `reset` · `savefig` `record` `export` ·
`menu` `hidemenu` `show` `hide` · `overview` `vars` `dims` `varinfo` ·
`exit`

Full reference: <https://gordi42.github.io/CDFViewer.jl/> (in a repo
checkout also under `docs/src/reference/` and `docs/src/usage/`).

## Rules

- Verify every visual output by Reading it before showing the user.
- Never leave a session running after the task is done (`session.sh stop`);
  check `session.sh status` if unsure.
- Kwargs persist across plot switches — `del limits` (etc.) when they would
  clash with the next plot.
