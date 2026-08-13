# Command Line Options

```
cdfviewer <files>... [options] [flags]
```

One or more NetCDF files, or a single zarr store, are required. All other
arguments are optional. A typical invocation opens a file with a complete
plot description.

```bash
cdfviewer demo.nc -v temperature -x lon -y lat -p heatmap --dims="time=5" -a time
```

## Positional arguments

| Argument | Description |
|:---------|:------------|
| `files` | Path(s) to the NetCDF file(s) to open (one or more), or a single zarr store directory (zarr format v2 only, v3 stores are detected but not yet supported). Combining multiple paths (multi-file aggregation) is NetCDF-only. |

## Options

| Option | Short | Description |
|:-------|:------|:------------|
| `--var` | `-v` | Variable to plot (`-v u,v` names both components of a vector plot) |
| `--x-axis` | `-x` | X-axis variable |
| `--y-axis` | `-y` | Y-axis variable |
| `--z-axis` | `-z` | Z-axis variable (for 3D plots) |
| `--plot_type` | `-p` | Type of plot to generate (e.g., contour, surface, scatter) |
| `--over` | | Variable to overlay on the same axis; repeatable, once per layer (`--over='u,v'` names both components of a vector layer) |
| `--over-plot` | | Plot type of the overlay, matched by position to `--over`; repeatable |
| `--kwargs` | | Additional keyword arguments for the plot (as a Julia expression) |
| `--dims` | | Dimension indices as key=index pairs, e.g., `--dims="time=5,lat=10"` |
| `--ani-dim` | `-a` | Dimension to use for animation |
| `--saveoptions` | `-s` | Options for saving the figure (as a Julia expression) |
| `--grid` | `-g` | Path to a grid file providing coordinates that are not stored in the data file(s) (e.g. an ICON grid file) |
| `--theme` | | Makie theme to draw in: `minimal` (the default), `light`, `dark`, `black`, or `ggplot2` (see [Themes](../usage/customization.md#Themes)) |

## Flags

| Flag | Description |
|:-----|:------------|
| `--savefig` | Only save the figure to file and exit |
| `--record` | Only record the animation to a video file and exit |
| `--menu` | Show the menu directly on start |
| `--use-local` | Use a local directory for temporary operations to improve performance (see [Configuration](../usage/configuration.md)) |
| `--no-grid-search` | Disable the automatic search for a matching grid file |
| `--no-summary` | Do not print the dataset overview when a file is opened |

## Notes

- `--kwargs` and `--saveoptions` take the same `key=value` expressions as
  the corresponding REPL input. Quote them in the shell, e.g.
  `--kwargs='colormap=:viridis, title="My Plot"'`.
- `--over` may be given several times, once per overlaid layer, and each
  one is drawn with the `--over-plot` in the same position. A keyword aimed
  at a single layer carries its prefix, e.g.
  `--kwargs='over.levels=10, over2.arrows=(20, 14)'` (see
  [Overlaying Fields](../usage/overlays.md)).
- `--savefig` and `--record` run headlessly. No window is opened, the file
  is written, and the program exits (see
  [Saving and Recording](../usage/saving.md)).
- The `export` REPL command prints a ready-made argument string that
  reproduces the current session.
