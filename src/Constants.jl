module Constants

const DIMENSION_LABELS = ["X", "Y", "Z"]
const NOT_SELECTED_LABEL = "Not Selected"
const NO_DIM_SELECTED_LABEL = "  → No dimension selected"

const AXES_KW_HINTS = "e.g., xscale=log10, yscale=log10"
const PLOT_KW_HINTS = "e.g., colormap=:viridis, colorrange=(-1,1)"

const DATETIME_FORMAT = "yyyy-mm-dd HH:MM:SS"

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
end

const THEME_LIGHT = ThemeColors(
    :balance,
    :royalblue3,
)

end