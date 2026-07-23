# Configuration

CDFViewer reads an optional configuration file and a handful of environment
variables. Everything works without any configuration. These are the knobs
for adapting the viewer to your environment, such as HPC systems, shared
grid pools, or slow file systems.

## The configuration file

The configuration lives at `~/.config/cdfviewer/config.toml` (respecting
`XDG_CONFIG_HOME`), and the full path can be overridden with the
`CDFVIEWER_CONFIG` environment variable. Currently it configures the
[grid file search](unstructured.md).

```toml
[grid]
search = true                       # master switch for automatic search
search_dirs = [
    "~/grids",                      # your own grid collection
    "/pool/data/ICON/grids/public", # e.g. the pool on Levante
]
download = false                    # opt-in: fetch grid_file_uri if not found
download_dir = "~/.cache/cdfviewer/grids"
```

## Environment variables

| Variable | Default | Effect |
|:---------|:--------|:-------|
| `CDFVIEWER_HISTORY` | `~/.cdfviewer_history` | location of the REPL history file |
| `CDFVIEWER_CONFIG` | `~/.config/cdfviewer/config.toml` | location of the configuration file |
| `CDFVIEWER_USE_LOCAL` | `false` | set to `true` to make `--use-local` the default |
| `CDFVIEWER_LOCAL_DIR` | a temporary directory | the local directory used by `--use-local` |
| `XDG_CONFIG_HOME` | `~/.config` | base directory for the configuration file |

## Slow file systems and `--use-local`

Recording a video writes many frames to disk before assembling the final
file. On network file systems (as common on HPC login nodes), this can be
painfully slow. With the `--use-local` flag, CDFViewer performs temporary
file operations in a fast local directory and only moves the final result
to your working directory.

```bash
cdfviewer output.nc --use-local
```

Set `CDFVIEWER_USE_LOCAL=true` in your shell profile to make this the
default, and `CDFVIEWER_LOCAL_DIR` to control which local directory is
used.
