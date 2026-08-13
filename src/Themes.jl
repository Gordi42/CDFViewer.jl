module Themes

using Colors
using DataStructures
using Makie

import ..Constants

# ============================================================
#  The themes on offer
# ============================================================
#
# One entry per theme Makie ships. A theme decides the look and nothing
# else: the LaTeX fonts and the viewer's own label sizes are merged on top
# of every one of them, so switching never moves the layout.

const THEMES = OrderedDict{String, Function}(
    "minimal" => Makie.theme_minimal,
    "light" => Makie.theme_light,
    "dark" => Makie.theme_dark,
    "black" => Makie.theme_black,
    "ggplot2" => Makie.theme_ggplot2,
)

# The look the viewer has always had. `theme` reports this name when
# nothing else was asked for, and the export string leaves it out.
const DEFAULT_THEME = "minimal"

"The theme names, in the order they are offered."
theme_names()::Vector{String} = collect(keys(THEMES))

"""
    resolve(name)

The canonical name a word stands for, or `nothing` when it names no
theme. `theme_dark` is Makie's own spelling of `dark` and is taken as
well, and `default` names the look the viewer starts under.
"""
function resolve(name::AbstractString)::Union{Nothing, String}
    word = replace(lowercase(strip(String(name))), r"^theme_" => "")
    word == "default" && return DEFAULT_THEME
    haskey(THEMES, word) ? word : nothing
end

"What an unrecognised theme name is refused with."
unknown_theme_message(name::AbstractString)::String =
    "Unknown theme '$name'. Available themes: " * join(theme_names(), ", ")

# ============================================================
#  Installing a theme
# ============================================================

# The name of the theme that is installed. Makie keeps the theme itself in
# a global of its own (`set_theme!` writes it), so remembering which one it
# is belongs at the same scope; a session reads it back through
# `Controller.get_theme`.
const ACTIVE = Ref(DEFAULT_THEME)

# Reset after precompilation: the workload switches themes, and a `Ref` in
# a package image keeps whatever it held when the image was written.
__init__() = (ACTIVE[] = DEFAULT_THEME; nothing)

"""
    viewer_theme()

What the viewer adds to whichever theme is selected: the label and title
sizes it lays its figures out with, and lines that the data inspector
does not react to.
"""
viewer_theme()::Attributes = Theme(
    Axis = (
        xlabelsize = Constants.LABELSIZE,
        ylabelsize = Constants.LABELSIZE,
        titlesize = Constants.TITLESIZE,
    ),
    Axis3 = (
        xlabelsize = Constants.LABELSIZE,
        ylabelsize = Constants.LABELSIZE,
        zlabelsize = Constants.LABELSIZE,
        titlesize = Constants.TITLESIZE,
    ),
    Lines = (inspectable = false,)
)

"The theme a figure is built under: Makie's `name`, plus the viewer's own."
function composed_theme(name::String)::Attributes
    composed = merge(Makie.theme_latexfonts(), THEMES[name]())
    merge(composed, viewer_theme())
end

"The name of the theme that is installed."
active()::String = ACTIVE[]

"Install the theme that is already selected. Idempotent."
function apply!()::Nothing
    Makie.set_theme!(composed_theme(ACTIVE[]))
    nothing
end

"""
    activate!(name)

Make `name` the theme every figure built from now on is drawn under.

It has to run *before* the figures: a figure snapshots the global theme
at creation and never looks at it again, which is why changing the theme
of a running session means rebuilding both windows.
"""
function activate!(name::AbstractString)::Nothing
    haskey(THEMES, name) ||
        throw(ArgumentError(unknown_theme_message(name)))
    ACTIVE[] = String(name)
    apply!()
end

# ============================================================
#  Colors derived from the installed theme
# ============================================================

"""
Every color the viewer draws its own chrome in.

Derived from the theme that is installed rather than tabulated per theme.
A Makie theme fixes two colors everything else can be read off -- the
ground it paints on and the color it writes text in -- and each piece of
chrome is one of those or a blend of the two. That is what keeps black
coastlines off a black ground under a theme nobody wrote a table entry
for.

The colors the *data* is drawn in are deliberately not in here. A
diverging colormap and a mid-blue line read on any ground, so they stay
where the plot types define them.
"""
struct ThemeColors
    # the two the rest are read off
    background::RGBA{Float32}
    text::RGBA{Float32}
    # figure chrome
    land::RGBA{Float32}
    # menu chrome
    inactive_text::RGBA{Float32}
    inactive_slider_bar::RGBA{Float32}
    accent::RGBA{Float32}
    accent_dimmed::RGBA{Float32}
end

"The color the installed theme gives `key`."
theme_color(key::Symbol, fallback)::RGBA{Float32} =
    Makie.to_color(Makie.to_value(Makie.theme(key; default = fallback)))

"`background` dragged `t` of the way toward `foreground`, staying opaque."
blend(background::RGBA{Float32}, foreground::RGBA{Float32},
      t::Real)::RGBA{Float32} =
    RGBA{Float32}(
        (1 - t) * background.r + t * foreground.r,
        (1 - t) * background.g + t * foreground.g,
        (1 - t) * background.b + t * foreground.b,
        background.alpha,
    )

"""
    theme_colors()

Derive the chrome colors from the theme that is installed right now.

Cheap enough to call wherever a color is needed -- a handful of lookups
and some arithmetic -- so nothing caches it and nothing can go stale
after a switch.
"""
function theme_colors()::ThemeColors
    background = theme_color(:backgroundcolor, :white)
    text = theme_color(:textcolor, :black)
    ThemeColors(
        background,
        text,
        blend(background, text, Constants.LAND_BLEND),
        blend(background, text, Constants.INACTIVE_TEXT_BLEND),
        blend(background, text, Constants.SLIDER_BAR_BLEND),
        Makie.to_color(Constants.ACCENT_COLOR),
        Makie.to_color(Constants.ACCENT_DIMMED_COLOR),
    )
end

"The same color at another opacity."
with_alpha(color::RGBA{Float32}, alpha::Real)::RGBA{Float32} =
    RGBA{Float32}(color.r, color.g, color.b, alpha)

"How bright a color reads, ignoring its opacity."
luminance(color::RGBA{Float32})::Float32 =
    Float32(gray(convert(Gray, RGB(color.r, color.g, color.b))))

"""
    readable_on(surface)

Whichever of the theme's two colors reads against `surface`.

Some widgets Makie paints in a color of their own whatever the theme
says -- a button's face is light gray under all five -- while the text on
them inherits the theme's text color. On a dark theme that puts white
lettering on a white button. The label takes this instead: the theme's
text color wherever it works, and its background color where the two
have swapped ends.
"""
function readable_on(surface::RGBA{Float32})::RGBA{Float32}
    colors = theme_colors()
    distance(color) = abs(luminance(color) - luminance(surface))
    distance(colors.text) >= distance(colors.background) ?
        colors.text : colors.background
end

"The color a button's resting label is drawn in."
widget_label_color()::RGBA{Float32} =
    readable_on(Makie.to_color(Constants.WIDGET_FACE_COLOR))

end # module
