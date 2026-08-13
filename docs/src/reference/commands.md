# REPL Commands

All commands available at the `CDFViewer>` prompt, grouped by purpose. In
the usage column, `<argument>` is required and `[argument]` is optional.
Omitting an optional argument of a selection command opens an interactive
picker in the terminal.

Any input line containing `key=value` pairs that does not start with a
command name is applied as plot keyword arguments (see
[Customizing Plots](../usage/customization.md)).

## Plot setup

| Command | Usage | Description |
|:--------|:------|:------------|
| `v` | `v [variable_name]` | Select a variable (`v u,v` selects both components of a vector plot) |
| `p` | `p [plot_type]` | Select a plot type |
| `x` | `x [variable_name]` | Select x-axis variable |
| `y` | `y [variable_name]` | Select y-axis variable |
| `z` | `z [variable_name]` | Select z-axis variable |

## Overlaid layers

Put `over` (or `over2`, `over3`, …) in front of the command you would give
the base field, and it addresses that layer instead. `base` addresses the
first layer explicitly. See [Overlaying Fields](../usage/overlays.md).

| Command | Usage | Description |
|:--------|:------|:------------|
| `over` | `over [variable\|off]` | Draw a second field on the same axis, or remove it; without an argument it reports what the layer draws |
| `over.v` | `over.v <variable>` | The same, spelled out (needed for a variable called `off`) |
| `over.p` | `over.p <plot_type>` | Plot type of the layer |

## Dimension selection

| Command | Usage | Description |
|:--------|:------|:------------|
| `isel` | `isel <dim_name> <index>` | Select index for a dimension |
| `sel` | `sel <dim_name> <value>` | Select value for a dimension (nearest grid point) |

## Playback

| Command | Usage | Description |
|:--------|:------|:------------|
| `play` | `play [dim_name]` | Toggle play/pause for animations |
| `pdim` | `pdim [dim_name]` | Set play dimension |
| `speed` | `speed [value]` | Set play speed (without a value it prints the current speed) |

## Plot manipulation

| Command | Usage | Description |
|:--------|:------|:------------|
| `del` | `del <kwarg_name>` | Delete keyword argument(s), restoring defaults |
| `refresh` | `refresh` | Refresh the plot |
| `reset` | `reset` | Reset plot settings to default |
| `theme` | `theme [name]` | Draw in another Makie theme (`minimal`, `light`, `dark`, `black`, `ggplot2`); without a name it reports the current one |

## Output

| Command | Usage | Description |
|:--------|:------|:------------|
| `savefig` | `savefig [filename=<filename>, px_per_unit=<Int>, overwrite=<Bool>]` | Save the current figure |
| `record` | `record [filename=<filename>, framerate=<Int>, range=<range>, overwrite=<Bool>]` | Record a movie |
| `export` | `export` | Print command line arguments reproducing the session |

## Windows

| Command | Usage | Description |
|:--------|:------|:------------|
| `show` | `show` | Show the figure window |
| `hide` | `hide` | Hide the figure window |
| `menu` | `menu` | Show the menu window |
| `hidemenu` | `hidemenu` | Hide the menu window |

## Information

| Command | Usage | Description |
|:--------|:------|:------------|
| `help` | `help` | List all commands |
| `overview` | `overview` | Show an overview of the dataset |
| `vars` | `vars` | List the variables |
| `varinfo` | `varinfo [variable_name]` | Show metadata of a variable |
| `dims` | `dims` | List dimensions with their current values |
| `plots` | `plots` | List the plot types |
| `conf` | `conf` | Show the current plot configuration |
| `kwargs` | `kwargs [category]` | List available keyword arguments (`figure`, `axis`, `plot`, `colorbar`, `range`) |
| `get` | `get <kwarg_name>` | Show the value of a keyword argument (a bare name reports the base layer; ask for `over.colormap` to reach an overlay) |

## Exiting

`exit`, `quit`, or `q` close the application.
