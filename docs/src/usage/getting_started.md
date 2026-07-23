# Getting Started

This page walks you through a first session. You will open a file, read the
dataset overview, and make a plot. All following examples use a small
synthetic weather dataset `demo.nc`, and every output and figure you see in
this manual is produced by the real application at documentation build time.

## Opening a file

Pass one or more NetCDF files on the command line (see
[Installation](../installation.md) for how to set up the `cdfviewer`
command).

```bash
cdfviewer demo.nc
```

Zarr stores work the same way. Pass the store directory instead of a file
(`cdfviewer output.zarr`). A single zarr store is supported per session,
while opening multiple paths at once (multi-file aggregation) is
NetCDF-only. Only zarr format v2 can be read. v3 stores (`zarr.json`
metadata) are detected, but the Julia zarr stack does not support them yet,
so CDFViewer refuses them with an explanatory error.

When the file is opened, CDFViewer prints a compact overview of the
dataset. It lists the dimension sizes, a coordinate block with units and
value ranges, and a table of the data variables.

```@example gs
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
print_overview(session) # hide
```

After the overview, a `CDFViewer>` prompt appears. This is the command REPL,
the keyboard-driven way to control the viewer. You can reprint the overview
at any time with the `overview` command, or suppress it at startup with
`--no-summary`.

## Your first plot

Making a plot takes three choices. You select a variable (`v`), the plot
axes (`x`, `y`, `z`), and a plot type (`p`). The first example plots a
temperature map.

```@example gs
repl(session, "v temperature", "x lon", "y lat", "p heatmap") # hide
```

As soon as a valid plot type is selected, the figure window opens.

```@example gs
plot_figure(session) # hide
```

Every command completes the moment you press Enter, and the plot updates
live. Type `help` for the full command list, or press TAB anywhere for
completion (commands, variable names, plot types, and keyword arguments are
all completed).

## Fixing the remaining dimensions

Our `temperature` variable has four dimensions but the heatmap shows only
`lon` and `lat`. The remaining dimensions `lev` and `time` are fixed at
their first index. Change them with `isel` (by index) or `sel` (by
coordinate value).

```@example gs
repl(session, "isel time 12", "sel lev 4.0") # hide
```

`sel` snaps to the nearest coordinate value, so you don't have to know the
exact grid points.

```@example gs
close_viewer!(session) # hide
nothing # hide
```

## Exploring with the mouse

The figure window is fully interactive.

- **Hover** over the data to inspect it. A tooltip shows the exact value
  under the cursor.
- **Scroll** to zoom, **right-drag** to pan, **left-drag** to zoom into a
  rubber-band selection, and **Ctrl + left-click** to reset the view.
- In 3D plots (`surface`, `wireframe`, `volume`, `contour3d`),
  **left-drag** rotates the camera instead.

On geographic maps, drag-panning is disabled by default so the projection
stays put. Unlock it with the `moveable=true` keyword (see
[Customizing Plots](customization.md)).

## The two windows

CDFViewer manages two windows. The **figure window** shows the plot, and an
optional **menu window** offers dropdown menus, sliders, and buttons that
mirror every REPL command. Open the menu with the `menu` command (or start
with `--menu`). See [The Menu Window](menu.md).

## Where to go next

- [The Command REPL](repl.md) explains history, completion, and line
  editing.
- [Selecting Data](selecting_data.md) treats variables, axes, and
  coordinates in depth.
- [Plot Types](plot_types.md) shows all nine plot types with examples.
- [Customizing Plots](customization.md) covers colormaps, labels, and map
  projections.
- [Animation and Playback](animation.md) plays a dimension like a movie.
- [Saving and Recording](saving.md) exports figures, videos, and sessions.
