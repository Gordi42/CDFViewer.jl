# Plot Types

CDFViewer ships eleven plot types, selected with the `p` command or the
*Plot Settings* menu. Which types are offered depends on how many plot axes
are assigned. A line plot needs one axis, a heatmap two, and volume
rendering three. The `plots` command lists all types.

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
| `quiver` | 2 | yes | arrows of a two-component field |
| `streamplot` | 2 | yes | streamlines of a two-component field |
| `surface` | 2 | yes | 3D surface, height = value |
| `wireframe` | 2 | no | 3D surface as a wire mesh |
| `volume` | 3 | yes | volume rendering |
| `contour3d` | 3 | yes | 3D isosurfaces |

`heatmap`, `contour`, `contourf`, `quiver`, and `streamplot` can also be
drawn on geographic map projections (see
[Customizing Plots](customization.md)).

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

## Quiver and streamplot (vector fields)

Wind and current are stored as two variables, one component each. `quiver`
and `streamplot` draw both at once, so they need two variables instead of
one. Name them in a single comma-separated token.

```@example pt
run!(session, "v u,v", "x lon", "y lat", "p quiver") # hide
plot_figure(session) # hide
```

Selecting one of these types with only one variable set looks for the
partner by name: `u` finds `v`, `uas` finds `vas`, `U10` finds `V10`. The
guess counts only when the dataset really holds that variable over the same
dimensions, so `p quiver` after `v u` usually needs no second name at all.
The colors are the magnitude of the vector, which is why both types carry a
colorbar and why they use a sequential colormap rather than the diverging
default.

The labels follow. The title names both components, with the unit they
share written once (`Eastward wind / Northward wind [m s-1]`), while
`cbarlabel="auto"` names what the colors actually stand for
(`|(u, v)| [m s-1]`). Components with different units get no unit at all
rather than a misleading one, and an explicit `title=` or `cbarlabel=`
overrides either.

How many arrows are drawn is a target count per axis, not a grid stride, so
it stays put when the grid underneath changes.

```@example pt
run!(session, "arrows=(40, 24)") # hide
plot_figure(session) # hide
```

How long they are drawn is decided on screen: the fastest arrows of a
frame span nine tenths of the gap to their neighbours, and every one of
them points where its own vector points. That is what a section needs,
whose two axes carry different quantities -- 45 km along it against 150 m
down it -- where a single length in data units is either invisible along
the one or reaches across the whole figure along the other. A section
draws its arrows the length a map draws them, and a resized window lays
them out again.

`lengthscale=` fixes that length instead, as the number of pixels one unit
of speed is drawn at. It is what two figures need to be read against each
other, where the same wind has to be the same arrow in both -- the
automatic scale is fitted to each frame's own grid and speeds. On a map,
where the arrows stay in the projection's own coordinates, the unit is
degrees per unit speed rather than pixels, and `del lengthscale` goes back
to the automatic scale either way.

| Keyword | Default | Effect |
|:--------|:--------|:-------|
| `arrows=(24, 16)` | `(24, 16)` | how many arrows to aim for along x and y |
| `every=4` | (none) | draw every n-th grid point instead, exactly |
| `minspeed=9` | (none) | leave everything slower than this undrawn |
| `lengthscale=40` | (none) | draw one unit of speed this many pixels long |

`streamplot` follows the field instead of sampling it, so `arrows` does not
apply to it. Its lines are short on purpose: each one runs 10% of the
shorter side of the domain in either direction from where it starts. A
long line ends where it runs into a line drawn before it, so a small
change in the data reshuffles which lines exist at all and an animation of
them boils. A short line ends at its own length instead and stays put from
frame to frame.

How many are drawn is Makie's own `density`, the fraction of the seeding
grid that gets filled. It defaults to `0.5`, so there is room to go both
ways; `gridsize`, `stepsize`, `maxsteps` and `arrow_size` are available as
usual, and `maxsteps=500` gives you the long lines back.

```@example pt
run!(session, "del arrows", "p streamplot") # hide
plot_figure(session) # hide
```

### Leaving out the slow parts

Streamlines drawn where the field barely moves are noise: they wander, and
they change from frame to frame. `minspeed` leaves them out.

```@example pt
run!(session, "minspeed=9") # hide
plot_figure(session) # hide
```

The value is a speed in the data's own units, and the colorbar is already
showing you that range -- read a value off it and type it. It is
deliberately not a fraction of the fastest wind in the frame: that would
be recomputed on every frame, so the blank region itself would move as the
data moves. An absolute cutoff holds still for a whole playback, the same
way a pinned color range does.

`minspeed` works on `quiver` as well, where it drops the arrows rather than
the lines, and `del minspeed` draws everything again.

### One color for the whole field

The colors are the magnitude of the vector by default. `color=` paints the
whole field in a single color instead, which is what you want when the
arrows sit over another field and the colors belong to that one.

```@example pt
run!(session, "del minspeed", "p quiver", "color=:black, cbar=false") # hide
plot_figure(session) # hide
```

The bar would otherwise go on showing a magnitude the arrows no longer
carry, so the two go together: `color=:black, cbar=false`. Any color Makie
accepts works, `(:black, 0.6)` included, and `del color` brings the
magnitude colors back.

### On a map

On a map both types are drawn in longitude/latitude and projected
afterwards, which needs two corrections you do not have to ask for. Arrows
are stretched by `1/cos(latitude)` so a steady eastward wind keeps its
drawn length toward the poles, and on a *global* domain an arrow whose tip
would cross the ±180° seam is dropped rather than smeared across the map.
A regional cut-out has no seam, so nothing is dropped there.

```@example pt
run!(session, "del color cbar", "proj=\"+proj=moll\"") # hide
plot_figure(session) # hide
```

```@example pt
run!(session, "del proj", "p heatmap", "v temperature") # hide
nothing # hide
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
