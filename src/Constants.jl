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

const FIGSIZE = (800, 600)
const LABELSIZE = 20
const TITLESIZE = 24

# ============================================
#  PLOT TYPES
# ============================================
const PLOT_DEFAULT_1D = "line"
const PLOT_DEFAULT_2D = "heatmap"
const PLOT_DEFAULT_3D = "volume"

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