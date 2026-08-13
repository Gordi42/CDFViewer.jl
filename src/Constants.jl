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
# label -- but never smaller than this.
const TITLESIZE_MIN = 12.0

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
const STREAMPLOT_GRIDSIZE = (80, 50)
const STREAMPLOT_STEPS = 200

# How far one streamline runs in each direction, as a fraction of the
# shorter side of the domain, and how much of the seeding grid gets
# filled.
#
# These are what keep an animation from boiling. Makie seeds its
# streamlines on the cells of the grid above, in a fixed quasirandom
# order, and marks every cell a line passes through as taken: a seed
# whose cell is already taken draws nothing, and a line that runs into a
# taken cell stops there (`Makie/src/basic_recipes/streamplot.jl`: the
# `mask[c]` test at the seed, the `!mask[idx]` break in the integration).
# With Makie's own `maxsteps` (500) no line ever reaches the step cap --
# they all end by colliding with an earlier line -- so which lines exist
# is decided by the order the lines happen to be drawn in. One line
# shifting by a cell then flips whole streamlines on and off.
#
# A cap short enough that a line ends geometrically instead breaks that
# chain: it leaves fewer cells taken, so nearly every seed fires, and the
# lines that do collide were short anyway. Measured on a drifting wind
# field over eight frames, the seeds that survive into the next frame go
# from 25% to 94%, and the drawn line pixels from 33% to 71%. The finer
# seeding grid spreads the lines out more evenly and the halved density
# keeps the picture as full as it was -- the same amount of line, in more
# and shorter pieces -- and the shorter lines are the cheaper ones: one
# frame of the field above costs 32 ms instead of 49.
const STREAMPLOT_LENGTH = 0.10
const STREAMPLOT_MAXSTEPS = round(Int, STREAMPLOT_LENGTH * STREAMPLOT_STEPS)
const STREAMPLOT_DENSITY = 0.5

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