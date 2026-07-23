# Plot Types

CDFViewer ships nine plot types, selected with the `p` command or the *Plot
Settings* menu. Which types are offered depends on how many plot axes are
assigned. A line plot needs one axis, a heatmap two, and volume rendering
three. The `plots` command lists all types.

```@example pt
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
repl(session, "plots") # hide
```

| Plot type | Axes | Colorbar | Description |
|:----------|:----:|:--------:|:------------|
| `line` | 1 | no | line plot |
| `scatter` | 1 | no | scatter plot |
| `heatmap` | 2 | yes | colored image of the field |
| `contour` | 2 | no | contour lines |
| `contourf` | 2 | yes | filled contours |
| `surface` | 2 | yes | 3D surface, height = value |
| `wireframe` | 2 | no | 3D surface as a wire mesh |
| `volume` | 3 | yes | volume rendering |
| `contour3d` | 3 | yes | 3D isosurfaces |

`heatmap`, `contour`, and `contourf` can also be drawn on geographic map
projections (see [Customizing Plots](customization.md)).

## Line and scatter (1D)

With a single axis assigned, the variable is drawn against that coordinate.
The first example draws the humidity at one grid point over time.

```@example pt
repl(session, "v humidity", "x time", "p line") # hide
```

```@example pt
plot_figure(session) # hide
```

`scatter` shows the same data as individual points.

```@example pt
run!(session, "p scatter") # hide
plot_figure(session) # hide
```

## Heatmap, contour, and contourf (2D)

Two assigned axes give you the classic map-style views. The default 2D type
is `heatmap`.

```@example pt
run!(session, "v temperature", "x lon", "y lat", "p heatmap") # hide
plot_figure(session) # hide
```

`contour` draws contour lines, `contourf` filled contour bands.

```@example pt
run!(session, "p contourf") # hide
plot_figure(session) # hide
```

## Surface and wireframe (2D data in 3D)

CDFViewer is just as handy for idealized, non-geographic setups, so the
remaining examples use a different dataset. `wave.nc` contains a circular
surface wave expanding in a 2 km × 2 km box. `surface` and `wireframe` take
two axes and render the field as a height surface in a 3D axis that you can
rotate with the mouse.

```@example pt
close_viewer!(session) # hide
session = open_viewer(demo_file("wave.nc")) # hide
repl(session, "v eta", "x x", "y y", "isel time 25", "p surface", "limits=(0, 2000, 0, 2000, -6, 6)") # hide
```

```@example pt
plot_figure(session) # hide
```

`wireframe` shows the same surface as a wire mesh, most useful for coarser
grids where the individual cells are of interest.

## Volume and contour3d (3D)

With three axes assigned, the field is rendered in 3D. `contour3d` draws
isosurfaces, here the concentric pressure rings of the same dataset.

```@example pt
run!(session, "del limits", "v pwave", "z z", "p contour3d") # hide
plot_figure(session) # hide
```

`volume` renders the full 3D field as a translucent volume instead, best
suited for smooth, space-filling fields.

```@example pt
close_viewer!(session) # hide
nothing # hide
```

!!! tip
    All 3D views (`surface`, `wireframe`, `volume`, `contour3d`) can be
    rotated and zoomed with the mouse in the figure window.
