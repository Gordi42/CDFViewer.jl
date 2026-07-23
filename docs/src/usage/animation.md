# Animation and Playback

Any dimension that is not on a plot axis can be played like a movie. The
viewer advances the dimension's index frame by frame and the plot updates
live. This is the quickest way to scan through time steps, vertical levels,
or ensemble members.

## Playing a dimension

Three commands control playback.

- `play [dim]` toggles play/pause and optionally selects the dimension
  first.
- `pdim [dim]` sets the dimension to animate without starting playback.
- `speed [value]` sets the playback speed. Values below 1 slow the
  animation down and values above 1 skip indices for faster scanning.

The example animates an idealized dataset, a circular surface wave
expanding in a 2 km × 2 km box, drawn as a 3D surface.

```@example anim
using Main.DocHelpers # hide
session = open_viewer(demo_file("wave.nc")) # hide
repl(session, "v eta", "x x", "y y", "p surface", "pdim time", "play") # hide
```

A second `play` pauses. In the [menu window](menu.md), the *Play* row offers
the same controls. A toggle, a speed slider, and the dimension dropdown sit
next to a label that shows the current coordinate value as the animation
runs.

You can also start animating right from the command line. Appending
`-a time` to the arguments opens the viewer with `time` already playing.

## Labelling the current frame

A recorded video carries no menu, so the frame itself has to say where in
the animation it is. The current value of the play dimension is therefore
shown right of the title, with the title on the left of the same row, on
every axis type, 3D included.

Nothing shifts while the animation runs. The label is compiled into static
text and value slots, and each slot is exactly as wide as the widest value
its axis can produce, so the text around a changing number stays pinned
and the number grows into its own slot.

The text is a template. `{name}` is the dimension's long name, `{value}`
its current value including the unit, `{rawvalue}` the value without it,
and `{unit}` and `{index}` the unit and the 1-based frame number. Every
changing placeholder gets its own slot, so a template may mix several.

```@example anim
repl(session, "animlabel=\"t = {rawvalue} s (frame {index})\"") # hide
```

```@example anim
plot_figure(session) # hide
```

`animlabelpos=:overlay` draws the label inside the plot area instead.
`animlabelcorner` picks its corner, and `animlabelbg` controls the
translucent box that keeps it readable over the data. `false` removes the
box and any color replaces it.

```@example anim
repl(session, "del animlabel", "animlabelpos=:overlay, animlabelcorner=:rt, animlabelbg=(:black, 0.3)") # hide
```

```@example anim
plot_figure(session) # hide
```

Numeric axes derive their format from the axis itself, so every frame
renders with the same number of digits (`0.5`, `1.0`, `1.5` rather than
`0.5`, `1`, `1.5`). Changing widths would make the value wobble in place.
Set `animlabelnumfmt` to a printf spec to override it, and
`animlabeldateformat` to shorten the timestamps of date axes.

| Keyword | Default | Effect |
|:--------|:--------|:-------|
| `animlabel=true` | `true` | `false` hides the label, a string sets the template |
| `animlabelpos=:title` | `:title` | `:title` (right of the title) or `:overlay` |
| `animlabelnumfmt="%.1f"` | `"auto"` | printf format for numeric axes (auto derives it from the axis) |
| `animlabeldateformat="yyyy-mm-dd"` | `"yyyy-mm-dd HH:MM:SS"` | date format for time axes |
| `animlabelcorner=:lt` | `:lt` | the corner for `:overlay` (`:lt`, `:rt`, `:lb`, or `:rb`) |
| `animlabelbg=true` | `true` | box behind the `:overlay` label (a color replaces it) |
| `animlabelsize=16` | `20` | fontsize of the label (slots resize with it) |

```@example anim
repl(session, "reset") # hide
```

!!! note
    Only the play dimension is labelled. Other dimensions held at a fixed
    index are not shown, and nothing is drawn until `pdim` selects a
    dimension. Set `animlabel=false` to turn the label off entirely.

## Recording an animation

The `record` command captures one full cycle of the play dimension to a
video file. The file extension selects the format (MP4, MKV, WebM, or GIF).
Before recording, it pays off to pin the color range and the axis limits,
so they do not rescale from frame to frame.

```@example anim
run!(session, "play") # hide
repl(session, "colorrange=(-3, 3), limits=(0, 2000, 0, 2000, -6, 6)", "record filename=animation.mp4, framerate=24") # hide
publish_asset("animation.mp4", "animation") # hide
close_viewer!(session) # hide
```

```@raw html
<video autoplay controls muted loop playsinline width="600" src="animation.mp4"></video>
```

The `framerate` and the frame `range` can be set as options. See
[Saving and Recording](saving.md) for all recording options and for
non-interactive (batch) recording with `--record`.
