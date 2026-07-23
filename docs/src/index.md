# CDFViewer.jl

CDFViewer is an interactive viewer for NetCDF files and zarr stores. It opens
a dataset straight from your terminal and lets you explore every variable
with sliders, menus, and a command prompt. The same session produces
publication-ready figures, animated recordings, and reproducible session
exports, all rendered with [GLMakie](https://docs.makie.org/stable/).

```@example hero
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
run!(session, "v temperature", "x lon", "y lat", "p contourf", "geographic=true", "xticklabelsvisible=false") # hide
plot_figure(session) # hide
```

## Features

- Open any NetCDF file or zarr store and get a plot with a handful of
  keystrokes, without writing a script or a notebook.
- A `CDFViewer>` prompt with tab completion, persistent history, and reverse
  search drives the whole application from the keyboard.
- Every setting is also available in a menu window with dropdown menus,
  sliders, and buttons. Both interfaces stay in sync.
- Nine plot types cover line and scatter plots, heatmaps, contours, 3D
  surfaces, and volume rendering.
- 2D fields can be drawn on geographic map projections with coastlines,
  land masses, and satellite imagery.
- Any dimension can be played like a movie and recorded to MP4, MKV, WebM,
  or GIF.
- ICON-style output on cell dimensions is interpolated on the fly, and
  external grid files are found automatically.
- The current view can be exported as a command line that recreates it
  exactly.

## Quick start

```bash
git clone https://github.com/Gordi42/CDFViewer.jl.git
cd CDFViewer.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using CDFViewer; julia_main()' your_file.nc
```

Then select a variable and a plot type at the prompt.

```
CDFViewer> v temperature
CDFViewer> p heatmap
```

```@example hero
close_viewer!(session) # hide
nothing # hide
```

Head over to [Installation](installation.md) for the full setup (including a
compiled system image for fast startup) and to
[Getting Started](usage/getting_started.md) for a guided tour.

## Manual outline

- [Installation](installation.md) covers installing, precompiling, and
  building a system image.
- [Getting Started](usage/getting_started.md) opens a file and makes a first
  plot.
- [The Command REPL](usage/repl.md) explains line editing, history, and
  completion.
- [The Menu Window](usage/menu.md) is the GUI counterpart of the REPL.
- [Selecting Data](usage/selecting_data.md) describes variables, axes, and
  fixed coordinates.
- [Plot Types](usage/plot_types.md) shows all nine plot types with examples.
- [Customizing Plots](usage/customization.md) covers keyword arguments,
  colormaps, and maps.
- [Animation and Playback](usage/animation.md) plays dimensions and records
  movies.
- [Saving and Recording](usage/saving.md) exports figures, videos, and
  sessions.
- [Unstructured Grids](usage/unstructured.md) handles ICON output,
  interpolation, and grid files.
- [Configuration](usage/configuration.md) documents the config file and
  environment variables.
- [Command Line Options](reference/cli.md) and
  [REPL Commands](reference/commands.md) are the full reference.
