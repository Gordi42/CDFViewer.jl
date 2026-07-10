# Animation and Playback

Any dimension that is not on a plot axis can be played like a movie: the
viewer advances the dimension's index frame by frame and the plot updates
live. This is the quickest way to scan through time steps, vertical levels,
or ensemble members.

## Playing a dimension

Three commands control playback:

- `play [dim]` — toggle play/pause (optionally selecting the dimension
  first),
- `pdim [dim]` — set the dimension to animate without starting playback,
- `speed [value]` — set the playback speed; values below 1 slow the
  animation down, values above 1 skip indices for faster scanning.

Let's animate an idealized dataset: a circular surface wave expanding in a
2 km × 2 km box, drawn as a 3D surface:

```@example anim
using Main.DocHelpers # hide
session = open_viewer(demo_file("wave.nc")) # hide
repl(session, "v eta", "x x", "y y", "p surface", "pdim time", "play") # hide
```

A second `play` pauses. In the [menu window](menu.md), the *Play* row offers
the same controls: a toggle, a speed slider, and the dimension dropdown, with
a label showing the current coordinate value as the animation runs.

You can also start animating right from the command line: appending
`-a time` to the arguments opens the viewer with `time` already playing.

## Recording an animation

The `record` command captures one full cycle of the play dimension to a
video file — MP4, MKV, WebM, or GIF, chosen by the file extension. Before
recording, it pays off to pin the color range and the axis limits, so they
do not rescale from frame to frame:

```@example anim
run!(session, "play") # hide
repl(session, "colorrange=(-3, 3), limits=(0, 2000, 0, 2000, -6, 6)", "record filename=animation.mp4, framerate=24") # hide
publish_asset("animation.mp4", "animation") # hide
close_viewer!(session) # hide
```

```@raw html
<video autoplay controls muted loop playsinline width="600" src="animation.mp4"></video>
```

The `framerate` and the frame `range` can be set as options; see
[Saving and Recording](saving.md) for all recording options and for
non-interactive (batch) recording with `--record`.
