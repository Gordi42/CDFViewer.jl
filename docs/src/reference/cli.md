# Command Line Options

```
cdfviewer <files>... [options] [flags]
```

One or more NetCDF files — or a single zarr store — are required; all other
arguments are optional. A typical invocation that opens a file with a
complete plot description:

```bash
cdfviewer demo.nc -v temperature -x lon -y lat -p heatmap --dims="time=5" -a time
```

## Positional arguments

| Argument | Description |
|:---------|:------------|
| `files` | Path(s) to the NetCDF file(s) to open (one or more), or a single zarr store directory (zarr format v2; v3 stores are detected but not yet supported). Combining multiple paths (multi-file aggregation) is NetCDF-only. |

## Options

| Option | Short | Description |
|:-------|:------|:------------|
| `--var` | `-v` | Variable to plot |
| `--x-axis` | `-x` | X-axis variable |
| `--y-axis` | `-y` | Y-axis variable |
| `--z-axis` | `-z` | Z-axis variable (for 3D plots) |
| `--plot_type` | `-p` | Type of plot to generate (e.g., contour, surface, scatter) |
| `--kwargs` | | Additional keyword arguments for the plot (as a Julia expression) |
| `--dims` | | Dimension indices as key=index pairs, e.g., `--dims="time=5,lat=10"` |
| `--ani-dim` | `-a` | Dimension to use for animation |
| `--saveoptions` | `-s` | Options for saving the figure (as a Julia expression) |
| `--grid` | `-g` | Path to a grid file providing coordinates that are not stored in the data file(s) (e.g. an ICON grid file) |

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
  the corresponding REPL input — quote them in the shell:
  `--kwargs='colormap=:viridis, title="My Plot"'`.
- `--savefig` and `--record` run headlessly: no window is opened, the file
  is written, and the program exits — see
  [Saving and Recording](../usage/saving.md).
- The `export` REPL command prints a ready-made argument string that
  reproduces the current session.
