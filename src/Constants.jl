module Constants

using Colors
using TOML

function get_version()::String
    project_toml = joinpath(@__DIR__, "..", "Project.toml")
    project_info = TOML.parsefile(project_toml)
    return project_info["version"]
end

const APP_VERSION = get_version()

const DIMENSION_LABELS = ["X", "Y", "Z"]
const NOT_SELECTED_LABEL = "Select"
const NO_DIM_SELECTED_LABEL = "  → No dimension selected"

const DATETIME_FORMAT = "yyyy-mm-dd HH:MM:SS"

# ============================================
#  Animated-axis label
# ============================================
# Printf spec used to render numeric coordinate values. "%g" keeps short
# decimals short and switches to scientific notation for extreme magnitudes;
# override with e.g. "%.3f" (fixed decimals) or "%.2e" (always scientific).
const NUMBER_FORMAT = "%g"

# Number format of the animated-axis label. "auto" derives one printf spec
# from the axis itself (fixed decimals or scientific, chosen from the step
# and magnitude), so every frame renders with the same number of digits --
# "0.5" -> "1.0" -> "1.5" instead of "0.5" -> "1" -> "1.5", whose changing
# widths make a right-aligned value dance inside its slot. Any explicit
# printf spec overrides the derivation.
const ANIMLABEL_NUMFMT = "auto"

# Template for the label showing the current value of the sliced/animated
# axes. Placeholders: {name} (long_name or dim name), {value} (formatted
# value including its unit), {rawvalue} (value without unit), {unit} and
# {index} (1-based index along the axis).
const ANIMLABEL_FORMAT = "{name}: {value}"

# Where the animated-axis label is drawn: :title puts it in its own
# layout row underneath the figure title, :overlay draws it inside the
# plot area.
const ANIMLABEL_POSITIONS = (:title, :overlay)
const ANIMLABEL_POSITION = :title

# Corner used by the :overlay position, and its inset from the axes
# corner in pixels.
const ANIMLABEL_CORNERS = (:lt, :rt, :lb, :rb)
const ANIMLABEL_CORNER = :lt
const ANIMLABEL_PADDING = 10

# Vertical gap between the plot box and the scene-anchored header text.
const HEADER_GAP = 8

# Leading between the two lines of a stacked header (title over label).
const HEADER_LINE_GAP = 2

# How many indices to sample when measuring the widest label a playback
# dimension can produce. Labels are padded to that width so they do not
# shift between frames; long axes are sampled rather than scanned in full.
const ANIMLABEL_WIDTH_SAMPLES = 512

# Optional background box behind the :overlay label, so it stays readable
# over busy data. `false` disables it, `true` paints the theme's own
# background at the opacity below, and any Makie color (e.g.
# `(:black, 0.4)`) overrides it.
const ANIMLABEL_BACKGROUND = true
const ANIMLABEL_BACKGROUND_ALPHA = 0.7
const ANIMLABEL_BACKGROUND_STROKE_ALPHA = 0.8
const ANIMLABEL_BACKGROUND_PADDING = 6
const ANIMLABEL_BACKGROUND_CORNERRADIUS = 5.0

const FIGSIZE = (800, 600)
const LABELSIZE = 20
const TITLESIZE = 24

# The title and the animated-axis label share one header line. A title too
# long for the space left over is drawn smaller rather than across the
# label -- but never smaller than this. Once even this size no longer
# fits, the two are stacked onto two lines instead of overlapping.
const TITLESIZE_MIN = 12.0

# The same floor for the animated-axis label, which only ever shrinks in
# the residual case: a label wider than the whole header line by itself.
const ANIMLABELSIZE_MIN = 12.0

# The shortest side an aspect-constrained axis is drawn at, in pixels of
# the figure. A data aspect letterboxes the axis inside its cell -- a
# 2400 m by 120 m shelf section is 20:1 and comes out as a wide, short
# band -- and past some point the short side stops being a plot at all.
# The data ratio is honoured until the axis would fall under this, and
# bounded from there on, so the geometry only ever gives way where it
# would have become unreadable anyway. Measured against the whole figure,
# which is a little larger than the cell the ticks and labels leave over,
# and so the bound follows `figsize`: a wide figure honours a wider
# domain.
const AXIS_MIN_EXTENT = 24

# Furniture around the plot box: the axis labels and their ticks, the
# header band, and the colorbar column. Near enough constant in pixels,
# so it comes off the figure before the data's shape is fitted into what
# is left. Measured off the default figure, which leaves a 635 by 480
# cell for the box.
const FIGURE_CHROME = (165, 120)

# Room for four stacked tick labels with air between them, which is what
# a wide plot box needs to still be read. `FIGSIZE` is a guess made
# before the file was ever opened; once a domain would come out shorter
# than this inside it, a window shaped like the data is the better guess
# -- and a plot recorded straight off the command line gets no second
# chance at one.
const AXIS_READABLE_HEIGHT = 60

# What such a window may grow and shrink to. It never goes narrower than
# the default: the colorbar sits in a column sized as a fraction of the
# figure width, and a narrower figure squeezes the bar out of its column.
# The shortest one is exactly a readable box plus its furniture, so the
# window stops shrinking at the same place the ratio below stops giving.
const FIGSIZE_MAX = (1600, 900)
const FIGSIZE_MIN = (FIGSIZE[1], AXIS_READABLE_HEIGHT + FIGURE_CHROME[2])

# The most elongated box the widest window can still show at that height.
# Under it the data's shape is exact in every window, auto-sized or not.
# Past it no window we would open could carry the geometry anyway -- a
# 6000 km by 4 km section is a line at any size, and the eye cannot read
# a slope off a hairline -- so the ratio is held here and the box fills
# its window instead of floating in it. This bounds the *wide* direction
# only: a tall box gives its width away, where the tick labels lie along
# the axis rather than stacking, and no attainable width fits them. There
# is nothing to aim for there beyond staying a plot at all, which is what
# `AXIS_MIN_EXTENT` is for.
const AXIS_MAX_RATIO = (FIGSIZE_MAX[1] - FIGURE_CHROME[1]) / AXIS_READABLE_HEIGHT

# `Axis` picks how many ticks to draw from the data range alone, so a box
# 67 pixels tall gets the seven labels a 500-pixel one gets and they lie
# on top of each other. Below a budget of this many labels the count
# follows the pixels instead, one label to this many of them. Only the y
# ticks: those stack, so what one needs is its own height and nothing
# else, while an x label lies along its axis and needs its own width --
# which is the text, and a guess there would be wrong more than right.
const TICKLABEL_HEIGHT = 30
const TICKLABEL_BUDGET = 4

# Colorbar label. The size follows the axis labels; color, font and
# padding mirror Makie's own Colorbar defaults under the viewer's theme,
# so an untouched option draws exactly as Makie would draw it. The color
# is the theme's own text color and therefore lives in `Themes`.
const CBARLABEL_FONT = "regular"
const CBARLABEL_PADDING = 5.0

const N_INTERPOLATION_POINTS = 500

const COORDINATE_ORDER_PRIORITY = Dict(
    "lon" => 1,
    "longitude" => 1,
    "x" => 1,
    "lat" => 2,
    "latitude" => 2,
    "y" => 2,
    "level" => 3,
    "depth" => 3,
    "z" => 3,
    "time" => 4,
)


# ============================================
#  PLOT TYPES
# ============================================
const PLOT_DEFAULT_1D = "line"
const PLOT_DEFAULT_2D = "heatmap"
const PLOT_DEFAULT_3D = "volume"

const GEOGRAPHIC_PLOT_TYPES = ["heatmap", "contour", "contourf", "quiver",
                               "streamplot"]
const GEOGRAPHIC_DATA_SCALES = [10, 50, 110]  # available map scales in meters

# ============================================
#  VECTOR PLOTS
# ============================================
# `quiver` and `streamplot` draw two variables at once (the zonal and the
# meridional component). How many components a plot type takes is its
# `nfields`; this is the largest one any type asks for.
const MAX_PLOT_COMPONENTS = 2

# Default number of arrows along each axis. A target count, not a stride:
# Ctrl-I rewrites the grid to the axis' pixel resolution, so a stride would
# multiply the arrow count with the window size while a target count holds.
const VECTOR_ARROWS = (24, 16)

# Fraction of a grid cell the strongest drawn arrow spans, and the quantile
# of |V| it is normalised to. The maximum would let one outlier gust shrink
# the whole field into invisibility.
const VECTOR_ARROW_FILL = 0.9
const VECTOR_SCALE_QUANTILE = 0.98

# Floor under cos(latitude) in the geographic arrow-length correction, so
# arrows next to the poles stay finite.
const COS_LATITUDE_FLOOR = 0.2

# Longitude coverage from which a domain counts as global, its two edges
# as one and the same meridian, and its edge arrows as worth masking; a
# regional cut-out has no seam to cross and keeps them. Compared against
# the span plus one cell, so grid resolution does not enter into it (see
# `Plotting.wraps_globally`).
const GLOBAL_LONGITUDE_SPAN = 350.0

# A magnitude is non-negative, so vector plots default to a sequential
# colormap instead of the app-wide diverging one, which washes out the
# middle of the range.
const VECTOR_COLORMAP = :viridis

# Streamline seeding grid, and the integrator step as a fraction of the
# domain. Makie's default stepsize (0.01) is in data units: on a lon/lat
# grid every step would travel 5 degrees.
const STREAMPLOT_GRIDSIZE = (40, 25)
const STREAMPLOT_STEPS = 200

# ============================================
#  Available File Formats
# ============================================
const IMAGE_FILE_FORMATS = [".png"]
const VIDEO_FILE_FORMATS = [".mkv", ".mp4", ".webm", ".gif"]

# ============================================
#  COLORS
# ============================================
#
# The viewer's own chrome takes its colors from the Makie theme that is
# installed (see `Themes`), so none of them is tabulated per theme. What
# is tabulated here is how far a color is dragged from the theme's
# background toward its text color: 0 is the ground, 1 the text.
#
# The three fractions below reproduce `:lightgray`, `:lightgray` again and
# `rgb(240, 240, 240)` on the black-on-white pair the app used to assume,
# which is what land, a grayed-out label and an idle slider bar were
# painted in before they were derived.
const LAND_BLEND = 0.17254901960784313
const INACTIVE_TEXT_BLEND = 0.17254901960784313
const SLIDER_BAR_BLEND = 0.058823529411764705

# The accent Makie paints every widget with. The sliders read it from here
# rather than from the theme so they keep agreeing with the buttons,
# toggles and dropdowns beside them, which use this pair under every theme.
const ACCENT_COLOR = parse(Colorant, "rgb(79, 122, 214)")
const ACCENT_DIMMED_COLOR = parse(Colorant, "rgb(174, 192, 230)")

# The face Makie paints a resting button in (`Button.buttoncolor`), light
# gray under every theme. A label drawn on it has to read against *it* and
# not against the window behind it, or a dark theme puts white lettering
# on a white button.
const WIDGET_FACE_COLOR = RGB{Float32}(0.94, 0.94, 0.94)

end