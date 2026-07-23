# Customizing Plots

Almost every visual aspect of a plot can be changed at runtime with keyword
arguments. Any input line containing `key=value` pairs — at the prompt or in
the *Plot Settings* text box of the menu — is applied to the current plot:

```@example cst
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
run!(session, "v temperature", "x lon", "y lat", "p heatmap") # hide
repl(session, "title=\"Air temperature\", xlabel=\"Longitude\", ylabel=\"Latitude\"") # hide
```

```@example cst
plot_figure(session) # hide
```

Values are parsed as Julia expressions: `:thermal` is a symbol, `(-20, 30)`
a tuple, `"Air temperature"` a string. Multiple pairs are separated by
commas.

## Where the keywords go

You never have to say *what* a keyword belongs to — CDFViewer routes each
one automatically to the figure, the axis, the plot object, the colorbar, or
the interpolation ranges, whichever accepts it. The `kwargs` command lists
what is available, grouped by these categories:

```
CDFViewer> kwargs figure
CDFViewer> kwargs axis
CDFViewer> kwargs plot
CDFViewer> kwargs colorbar
CDFViewer> kwargs range
```

Since the available keywords depend on the current plot type, the lists are
long; try them in a running session (TAB completion works on keyword names,
too).

## Colormap and color range

`colormap` accepts any [Makie colormap](https://docs.makie.org/stable/explanations/colors)
name, and `colorrange` pins the color scale — useful to compare different
time steps on the same scale, or before recording an animation:

```@example cst
repl(session, "colormap=:thermal, colorrange=(-20, 30)") # hide
```

```@example cst
plot_figure(session) # hide
```

The colorbar follows automatically. Deleting the keyword (`del colorrange`)
returns to automatic scaling.

## Contour levels and labels

Plot-specific keywords work the same way. A contour plot, for example, takes
the `levels` to draw (a number or an explicit range) and can label them
directly on the lines:

```@example cst
repl(session, "p contour", "levels=-30:5:30, labels=true") # hide
```

```@example cst
plot_figure(session) # hide
```

## Inspecting and resetting

`get` shows the current value of a keyword, `conf` lists everything you have
set, `del` removes keywords (restoring their defaults), and `reset` clears
all customizations at once:

```@example cst
repl(session, "get colormap", "conf", "del labels levels", "reset") # hide
```

## Figure settings

A few special keywords control the figure itself rather than the plot:

| Keyword | Default | Effect |
|:--------|:--------|:-------|
| `figsize=(800, 600)` | `(800, 600)` | size of the figure in pixels |
| `titlesize=28` | `24` | fontsize of the figure title |
| `xunit="km"` | – | render an axis in another unit — see [Axis units](@ref) |
| `cbar=true` | `true` | show or hide the colorbar |
| `moveable=true` | `true` | allow drag-panning with the mouse |
| `geographic=false` | `false` | draw on a geographic map projection |
| `proj="+proj=moll"` | – | map projection (PROJ string) |
| `scale=110` | `110` | coastline resolution in m: `10`, `50`, or `110` |
| `coastlines=true` | `true` | draw coastlines (geographic mode) |
| `land=false` | `false` | fill land masses (geographic mode) |
| `earth=false` | `false` | satellite image background (geographic mode) |

The label naming the dimensions that are not on a plot axis is configured
the same way, through its own `animlabel...` keywords — see
[Animation and Playback](animation.md#Labelling-the-current-frame).

## Geographic plots

For 2D fields on longitude/latitude axes, `geographic=true` switches the
axis to a map projection — `heatmap`, `contour`, and `contourf` support it.
The automatic longitude tick labels tend to bunch up at the curved map edge,
so we hide them here with a regular axis keyword:

```@example cst
run!(session, "p contourf") # hide
repl(session, "geographic=true, land=true, xticklabelsvisible=false") # hide
```

```@example cst
plot_figure(session) # hide
```

The projection can be any [PROJ](https://proj.org/) string, for example a
Mollweide projection:

```@example cst
run!(session, "proj=\"+proj=moll\"", "xticklabelsvisible=false") # hide
plot_figure(session) # hide
```

```@example cst
close_viewer!(session) # hide
nothing # hide
```

## Axis units

Coordinates are often stored in base units — meters, seconds, pascals —
while the domain is better read in a larger one: a field spanning
hundreds of kilometers draws meter ticks in scientific notation. The
`xunit`, `yunit`, and `zunit` keywords render an axis in another unit of
the same family:

```@example cstu
using Main.DocHelpers # hide
session = open_viewer(demo_file("wave.nc")) # hide
run!(session, "v eta", "x x", "y y", "p heatmap") # hide
repl(session, "xunit=\"km\", yunit=\"km\"") # hide
```

```@example cstu
plot_figure(session) # hide
```

Tick values are chosen to be round in the displayed unit, and the axis
label switches to it. Everything else stays in native coordinates: axis
`limits`, interpolation ranges, and the values shown by the data
inspector are unaffected — the conversion is purely visual.

Units convert only within their family:

| Family   | Units |
|:---------|:------|
| length   | `mm`, `cm`, `m`, `km` |
| time     | `s`, `min`, `h`, `d` |
| pressure | `Pa`, `hPa`, `mbar`, `kPa`, `dbar`, `bar` |

Asking for a unit the axis cannot convert to (say `xunit="bar"` on a
meter axis) keeps the native ticks and reports why; `del xunit` returns
to the native unit.

```@example cstu
close_viewer!(session) # hide
nothing # hide
```

!!! note
    Keyword arguments survive plot type switches where possible and can also
    be passed at startup with `--kwargs='colormap=:viridis, ...'` — see
    [Command Line Options](../reference/cli.md).
