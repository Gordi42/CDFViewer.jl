# Saving and Recording

CDFViewer writes three kinds of output. It saves still images of the
current figure, records videos of an animation, and prints a command-line
string that reproduces the whole session. All three are available as REPL
commands and as the
*Save*, *Record*, and *Export* buttons of the [menu window](menu.md).

## Saving figures

`savefig` writes the current figure as a PNG.

```@example sav
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
run!(session, "v temperature", "x lon", "y lat", "p heatmap") # hide
repl(session, "savefig filename=temperature.png") # hide
```

Two options control the output.

- `filename` sets the output path, and the `.png` extension is added if
  missing. If the file already exists, a number is appended
  (`temperature(1).png`) so nothing is overwritten.
- `px_per_unit` multiplies the resolution. A value of `2` doubles the pixel
  resolution at the same figure layout, for print-quality output.

Without a `filename`, a name is derived automatically. In the menu window,
the options are typed into the text box at the very bottom.

## Recording videos

`record` sweeps the play dimension once and writes a video. The format
follows the extension (`.mp4`, `.mkv`, `.webm`, or `.gif`).

```
CDFViewer> record filename=temperature.mp4, framerate=30
```

Three options control the recording.

- `filename` sets the output path, and the extension selects the codec.
- `framerate` sets the frames per second (default 30).
- `range` restricts the recorded frames, e.g. `range=1:12`.

The animated dimension is set with `pdim` (or the *Play* dropdown). See
[Animation and Playback](animation.md).

## Batch mode with `--savefig` and `--record`

Both outputs also work non-interactively, without opening any window. Pass a
complete plot description on the command line together with `--savefig` or
`--record`, and CDFViewer renders, writes the file, and exits.

```bash
cdfviewer demo.nc -v temperature -x lon -y lat -p heatmap \
    --savefig -s 'filename="temperature.png", px_per_unit=2'

cdfviewer demo.nc -v temperature -x lon -y lat -p heatmap -a time \
    --record -s 'filename="temperature.mp4", framerate=25'
```

This makes CDFViewer usable in scripts and batch jobs, for example to
render a figure for every file of a model run.

## Reproducing a session with `export`

After interactively tuning a plot, `export` prints the command line that
recreates the current state, including the variable, axes, plot type, fixed
indices, keyword arguments, and even the current axis limits.

```@example sav
run!(session, "isel time 6", "colormap=:balance, title=\"Air temperature\"") # hide
repl(session, "export") # hide
close_viewer!(session) # hide
```

Paste the printed arguments after `cdfviewer` to jump straight back to this
view, or combine them with `--savefig` for batch rendering.
