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

const PLOT_KW_HINTS = "e.g., colormap=:viridis, colorrange=(-1,1)"

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
# over busy data. `false` disables it, `true` uses the translucent default
# below, and any Makie colour (e.g. `(:black, 0.4)`) overrides it.
const ANIMLABEL_BACKGROUND = true
const ANIMLABEL_BACKGROUND_COLOR = (:white, 0.7)
const ANIMLABEL_BACKGROUND_PADDING = 6
const ANIMLABEL_BACKGROUND_CORNERRADIUS = 5.0

const FIGSIZE = (800, 600)
const LABELSIZE = 20
const TITLESIZE = 24

# Colorbar label. The size follows the axis labels; colour, font and
# padding mirror Makie's own Colorbar defaults under the viewer's theme,
# so an untouched option draws exactly as Makie would draw it.
const CBARLABEL_COLOR = :black
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
struct ThemeColors
    colormap::Symbol
    colorline::Symbol

    active_text_color::RGB
    inactive_text_color::RGB
    inactive_slider_bar_color::RGB
    accent_color::RGB
    accent_dimmed_color::RGB
end

const THEME_LIGHT = ThemeColors(
    :balance,
    :royalblue3,

    parse(Colorant, :black),
    parse(Colorant, :lightgray),
    parse(Colorant, "rgb(240, 240, 240)"),
    parse(Colorant, "rgb(79, 122, 214)"),
    parse(Colorant, "rgb(174, 192, 230)"),
)

end