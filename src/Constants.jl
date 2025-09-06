module Constants

using Colors


const DIMENSION_LABELS = ["X", "Y", "Z"]
const NOT_SELECTED_LABEL = "Not Selected"
const NO_DIM_SELECTED_LABEL = "  → No dimension selected"

const AXES_KW_HINTS = "e.g., xscale=log10, yscale=log10"
const PLOT_KW_HINTS = "e.g., colormap=:viridis, colorrange=(-1,1)"

const DATETIME_FORMAT = "yyyy-mm-dd HH:MM:SS"

const FIGSIZE = (1200, 800)
const LABELSIZE = 20
const TITLESIZE = 24

# ============================================
#  PLOT TYPES
# ============================================
const PLOT_INFO = "Info"
const PLOT_DEFAULT_1D = "line"
const PLOT_DEFAULT_2D = "heatmap"
const PLOT_DEFAULT_3D = "volume"

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