# CDFViewer.jl

CDFViewer is an interactive viewer for NetCDF files and zarr stores. It opens a dataset
straight from your terminal, lets you explore every variable with sliders,
menus, and a command prompt, and produces publication-ready figures, animated
recordings, and reproducible session exports — all powered by
[GLMakie](https://docs.makie.org/stable/).

```@example hero
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
run!(session, "v temperature", "x lon", "y lat", "p contourf", "geographic=true", "xticklabelsvisible=false") # hide
plot_figure(session) # hide
```

## Features

- **Quick look, zero code:** open any NetCDF file or zarr store and get a
  plot with a handful of keystrokes — no scripts, no notebooks.
- **Command REPL:** a `CDFViewer>` prompt with tab completion, persistent
  history, and reverse search drives the whole application from the keyboard.
- **Interactive menu:** every setting is also available in a GUI window with
  dropdown menus, sliders, and buttons — both interfaces stay in sync.
- **Nine plot types:** from line plots over heatmaps and filled contours to
  3D surfaces and volume rendering.
- **Geographic projections:** draw 2D fields on map projections with
  coastlines, land masses, and satellite imagery.
- **Animation and recording:** play any dimension like a movie and record it
  to MP4, MKV, WebM, or GIF.
- **Unstructured grids:** ICON-style output on cell dimensions is
  interpolated on the fly; external grid files are found automatically.
- **Reproducible sessions:** export the current view as a command line that
  recreates it exactly.

## Quick start

```bash
git clone https://github.com/Gordi42/CDFViewer.jl.git
cd CDFViewer.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using CDFViewer; julia_main()' your_file.nc
```

Then select a variable and a plot type at the prompt:

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

- [Installation](installation.md) — install, precompile, or build a system image.
- [Getting Started](usage/getting_started.md) — open a file and make your first plot.
- [The Command REPL](usage/repl.md) — line editing, history, and completion.
- [The Menu Window](usage/menu.md) — the GUI counterpart of the REPL.
- [Selecting Data](usage/selecting_data.md) — variables, axes, and fixed coordinates.
- [Plot Types](usage/plot_types.md) — all nine plot types with examples.
- [Customizing Plots](usage/customization.md) — keyword arguments, colormaps, and maps.
- [Animation and Playback](usage/animation.md) — play dimensions and record movies.
- [Saving and Recording](usage/saving.md) — figures, videos, and session export.
- [Unstructured Grids](usage/unstructured.md) — ICON output, interpolation, and grid files.
- [Configuration](usage/configuration.md) — config file and environment variables.
- [Command Line Options](reference/cli.md) and [REPL Commands](reference/commands.md) — full reference.
