# The Menu Window

Everything in CDFViewer can be controlled from two places: the
[command REPL](repl.md) in the terminal, and a menu window with dropdown
menus, sliders, and buttons. The two are always in sync — selecting a
variable at the prompt updates the menu, and vice versa. Use whichever fits
your workflow; they are two views of the same state.

The menu window is hidden by default. Open it with the `menu` command, close
it with `hidemenu`, or start the application with the `--menu` flag to show
it right away. The related commands `show` and `hide` control the figure
window instead.

```@example menu
using Main.DocHelpers # hide
using GLMakie: save # hide
session = open_viewer(demo_file("demo.nc")) # hide
run!(session, "v temperature", "x lon", "y lat", "p heatmap", "pdim time") # hide
save("menu_window.png", menu_figure(session)) # hide
nothing # hide
```

```@raw html
<img src="menu_window.png" alt="The menu window" width="400"
     style="border: 1px solid rgba(128, 128, 128, 0.6); border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.25);">
```

From top to bottom:

- **Variable** — the data variable to plot, one entry per variable in the
  dataset (the `v` command).
- **Plot Settings** — the plot type (`p`). The list is filtered to the
  types that match the number of selected axes. The text box below takes
  plot keyword arguments, exactly like typing them at the prompt — see
  [Customizing Plots](customization.md).
- **X / Y / Z** — assign dataset dimensions to the plot axes (`x`, `y`,
  `z`).
- **Play** — animate a dimension: the toggle starts and stops playback, the
  slider controls the speed, and the dropdown selects the dimension to
  animate. The value label below shows the current coordinate value of the
  animated dimension. See [Animation and Playback](animation.md).
- **Fixed Coordinates** — one slider per dimension that is not on a plot
  axis (the `isel`/`sel` commands). The toggle on the right controls
  whether the plot updates live while dragging a slider — turn it off for
  large datasets where every update is expensive.
- **Save / Record / Export** — write the current figure to an image, record
  an animation to a video, or print a command line that reproduces the
  session. The text box takes output options such as
  `filename="output.png"` — see [Saving and Recording](saving.md).

```@example menu
close_viewer!(session) # hide
nothing # hide
```

!!! tip
    In the figure window, press **Ctrl-I** to toggle the interpolation of
    unstructured variables — see [Unstructured Grids](unstructured.md).
