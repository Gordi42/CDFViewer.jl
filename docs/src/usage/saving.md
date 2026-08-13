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

Three options control the output.

- `filename` sets the output path, and the `.png` extension is added if
  missing.
- `px_per_unit` multiplies the resolution. A value of `2` doubles the pixel
  resolution at the same figure layout, for print-quality output.
- `overwrite` decides what a name already taken means (see
  [Writing over an earlier file](@ref)).

Without a `filename`, a name is derived automatically. All three stay
set until you change them, so the *Save* button of the menu writes with
whatever you gave last.

## Recording videos

`record` sweeps the play dimension once and writes a video. The format
follows the extension (`.mp4`, `.mkv`, `.webm`, or `.gif`).

```
CDFViewer> record filename=temperature.mp4, framerate=30
```

Four options control the recording.

- `filename` sets the output path, and the extension selects the codec.
- `framerate` sets the frames per second (default 30).
- `range` restricts the recorded frames, e.g. `range=1:12`.
- `overwrite` decides what a name already taken means (see
  [Writing over an earlier file](@ref)).

The animated dimension is set with `pdim` (or the *Play* dropdown). See
[Animation and Playback](animation.md).

## Writing over an earlier file

A name that is already taken is written over, and a line on stderr says
so. Both outputs are composed in a temporary file and moved into place
only once they are complete, so a render or a recording that fails
halfway never costs you the file that was there.

Overwriting is what a re-run wants. Recording `waves.mp4` a second time
after changing the plot leaves the newer take under the name you gave it,
rather than parking it in `waves(1).mp4` and leaving everything pointed
at the name -- a docs page, a script, a player you left open -- showing
the older one.

Pass `overwrite=false` for the other behaviour: the taken name is left
alone and the output goes to the next free `waves(1).mp4`,
`waves(2).mp4`, and so on. This is worth having when saving a series of
views by hand under one name.

```
CDFViewer> record filename=waves.mp4, overwrite=false
```

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

On a map the limits come out in longitude and latitude, the coordinates you
would type yourself, rather than in the metres the projection works in. A
view that no pair of meridians and parallels describes, one zoomed out past
the edge of its projection or straddling the ±180° seam, is exported without
its limits and reopens on the whole field.
