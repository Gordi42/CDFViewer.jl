# Selecting Data

Every plot in CDFViewer is defined by three choices: **which variable** to
show, **which dimensions** go on the plot axes, and **at which index** the
remaining dimensions are fixed. This page covers the commands for all three,
plus the commands for inspecting what the dataset contains.

## Inspecting the dataset

`vars` lists the variables, `dims` shows the dimensions of the current
variable together with their currently selected values, and `varinfo` prints
the full NetCDF metadata of a variable:

```@example sel
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
repl(session, "vars", "v temperature", "dims") # hide
```

```@example sel
repl(session, "varinfo humidity") # hide
```

The `overview` command reprints the dataset summary that was shown when the
file was opened.

## Choosing the plot axes

`x`, `y`, and `z` assign dimensions to the plot axes. How many axes you
assign determines which plot types are available: one axis for line and
scatter plots, two for heatmaps and contours, three for volume rendering
(see [Plot Types](plot_types.md)).

```@example sel
repl(session, "x lon", "y lat") # hide
```

Selecting a new variable keeps the axis assignments when they are compatible
with the new variable's dimensions.

## Fixing the remaining dimensions

Dimensions that are not on an axis are fixed at one index, which you move
either by index or by coordinate value:

- `isel <dim> <index>` selects by **i**nteger index (1-based),
- `sel <dim> <value>` selects by coordinate **value**, snapping to the
  nearest grid point.

```@example sel
repl(session, "isel time 6", "sel lev 8.0") # hide
close_viewer!(session) # hide
```

In the [menu window](menu.md), the same selection is available as the
*Fixed Coordinates* sliders.

!!! note
    Time coordinates with CF-conform units are decoded to dates, so the
    value labels show human-readable timestamps rather than raw numbers.
