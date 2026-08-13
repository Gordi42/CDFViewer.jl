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

"""
    composed_theme(name)

The theme a figure is built under: Makie's `name`, plus the viewer's own
sizes, plus how the menu window's widgets are painted under it.

The widget colors go in here rather than on the widgets themselves so that
they are in place the moment a `Block` is constructed -- which is the only
moment a `Block` reads a theme. It also keeps them out of the way of an
explicit keyword, which Makie gives priority over any theme entry.
"""
function composed_theme(name::String)::Attributes
    composed = merge(Makie.theme_latexfonts(), THEMES[name]())
    composed = merge(composed, viewer_theme())
    # the widget layer goes on last and fills in only what the theme left
    # unsaid, the same way the sizes above it do -- `merge` keeps what it
    # already has. None of Makie's five says anything about a widget, so
    # today the whole layer lands
    merge(composed, block_theme(theme_colors(composed)))
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
chrome is one of those, a blend of the two, or a fixed step off the
ground. That is what keeps black coastlines off a black ground under a
theme nobody wrote a table entry for.

One thing in here is not chrome: the diverging colormap a scalar field
starts out in. It is read off the same ground for the same reason -- a
colormap that is white in the middle puts the brightest band of the figure
through the middle of the range, which is what a light page wants and a
dark page does not. The line color of a 1D plot stays where the plot types
define it, since a mid-blue line reads on either ground.
"""
struct ThemeColors
    # the two the rest are read off
    background::RGBA{Float32}
    text::RGBA{Float32}
    # figure chrome
    land::RGBA{Float32}
    # the data's own starting colormap
    colormap::Symbol
    # menu chrome: the surfaces Makie paints the widgets themselves in
    widget_face::RGBA{Float32}
    menu_cell::RGBA{Float32}
    dropdown_arrow::RGBA{Float32}
    # menu chrome: what is drawn on top of them
    inactive_text::RGBA{Float32}
    inactive_slider_bar::RGBA{Float32}
    accent::RGBA{Float32}
    accent_dimmed::RGBA{Float32}
end

"The color the installed theme gives `key`."
theme_color(key::Symbol, fallback)::RGBA{Float32} =
    Makie.to_color(Makie.to_value(Makie.theme(key; default = fallback)))

"The color `theme` gives `key`, for a theme that is not installed yet."
theme_color(theme::Attributes, key::Symbol, fallback)::RGBA{Float32} =
    Makie.to_color(haskey(theme, key) ?
                   Makie.to_value(theme[key]) : fallback)

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
    theme_colors(theme)

Derive the chrome colors from the theme that is installed right now, or
from one that is only being composed.

Cheap enough to call wherever a color is needed -- a handful of lookups
and some arithmetic -- so nothing caches it and nothing can go stale
after a switch.
"""
theme_colors()::ThemeColors =
    derive_colors(theme_color(:backgroundcolor, :white),
                  theme_color(:textcolor, :black))

theme_colors(theme::Attributes)::ThemeColors =
    derive_colors(theme_color(theme, :backgroundcolor, :white),
                  theme_color(theme, :textcolor, :black))

"Everything a theme's ground and its text color imply."
function derive_colors(background::RGBA{Float32},
                       text::RGBA{Float32})::ThemeColors
    pole = contrast_pole(background)
    ThemeColors(
        background,
        text,
        blend(background, text, Constants.LAND_BLEND),
        is_dark(background) ? Constants.DARK_COLORMAP : Constants.COLORMAP,
        blend(background, pole, Constants.WIDGET_FACE_BLEND),
        blend(background, pole, Constants.MENU_CELL_BLEND),
        with_alpha(pole, Constants.DROPDOWN_ARROW_ALPHA),
        blend(background, text, Constants.INACTIVE_TEXT_BLEND),
        blend(background, pole, Constants.SLIDER_BAR_BLEND),
        Makie.to_color(Constants.ACCENT_COLOR),
        Makie.to_color(Constants.ACCENT_DIMMED_COLOR),
    )
end

"The same color at another opacity."
with_alpha(color::RGBA{Float32}, alpha::Real)::RGBA{Float32} =
    RGBA{Float32}(color.r, color.g, color.b, alpha)

"""
    opaque(color)

The same color with its alpha channel dropped.

A widget's face is a surface, never a film the page shows through, and
`blend` carries the ground's own alpha into everything read off it -- so a
theme painting on anything but a solid color would otherwise hand every
button and dropdown that transparency too. Dropping it also leaves the
colors in the `RGBf` Makie states its own in, which is what makes the
default theme reproduce them down to the type.
"""
opaque(color::RGBA{Float32})::RGB{Float32} =
    RGB{Float32}(color.r, color.g, color.b)

"How bright a color reads, ignoring its opacity."
luminance(color::RGBA{Float32})::Float32 =
    Float32(gray(convert(Gray, RGB(color.r, color.g, color.b))))

"Whether a color is dark enough to be read as a dark ground."
is_dark(color::RGBA{Float32})::Bool =
    luminance(color) < Constants.DARK_GROUND_LUMINANCE

"""
    contrast_pole(color)

The end of the gray scale a color stands out against: white over a dark
one, black over a light one.

Two things read off it. A widget's own surface is a fixed step off the
page -- `RGBf(0.94)` for a resting button on a white one -- and the step
has to keep its size under a theme that paints on something else. Taking
it toward the theme's *text* color instead would collapse it: `theme_dark`
writes in `gray45` on a `gray10` ground, so six percent of that distance
is a surface nobody can tell from the page it sits on. The pole is always
the full distance away.

The other is lettering that lands on a surface the theme had no say in --
the accent Makie lights an interactive widget up in. Neither of the
theme's own two colors is guaranteed to read on it, so the label takes the
pole instead, which is what Makie's own fixed `labelcolor_hover = :black`
and `labelcolor_active = :white` amount to.
"""
contrast_pole(color::RGBA{Float32})::RGBA{Float32} =
    is_dark(color) ? Makie.to_color(:white) : Makie.to_color(:black)

"""
    readable_on(surface)
    readable_on(colors, surface)

Whichever of the theme's two colors reads against `surface`.

A label has to contrast with the face of its own widget and not with the
window behind it. The two mostly agree, since a widget's face is only a
step off the ground, and staying inside the theme's own pair is what keeps
a `theme_dark` label the same `gray45` as every other label on the figure
rather than a white one nothing else on the page is written in.

Only for a surface the theme had no say in are both of its colors a bad
bet; `contrast_pole` covers that case.
"""
function readable_on(colors::ThemeColors,
                     surface::RGBA{Float32})::RGBA{Float32}
    distance(color) = abs(luminance(color) - luminance(surface))
    distance(colors.text) >= distance(colors.background) ?
        colors.text : colors.background
end

readable_on(surface::RGBA{Float32})::RGBA{Float32} =
    readable_on(theme_colors(), surface)

# ============================================================
#  How the menu window's widgets are painted
# ============================================================

"""
    block_theme(colors)

The surfaces of every `Block` the menu window is built from.

Makie's widgets carry their own colors, and the ones naming a surface are
fixed light greys and a fixed black arrow whatever theme is installed --
`Button.buttoncolor`, `Toggle.framecolor_inactive`, `Slider.color_inactive`
and `Menu.selection_cell_color_inactive` are all `RGBf(0.94)`, a dropdown
row is `RGBf(0.97)`, and `Menu.textcolor` is `:black` without even
inheriting the theme's. Makie's own `theme_dark` and `theme_black` restate
none of them, so a dark theme leaves a window of white widgets with black
lettering. Each is restated here as the same step off *this* theme's
ground, which reproduces Makie's own value exactly on a white page.

`Label` is not in here: its color already inherits `textcolor`, and a
`SliderGrid` is nothing but `Slider`s and `Label`s, so it is covered by
the two of them. Neither is the text of an open dropdown's rows, which
Makie draws with no color of its own and which therefore already inherits
`textcolor` -- `Menu.textcolor` names the closed dropdown's label alone.

The accent pair is left alone. It is what every interactive widget lights
up in under every theme, the coordinate sliders read the same pair out of
`Constants` so they agree with the dropdowns beside them, and it reads on
both grounds. Only the lettering that lands on it is derived, and off the
accent itself rather than off the theme, since the theme had no say in it.

One label cannot be reached that way: the row of an open dropdown that is
the current selection is painted in the accent, but Makie draws all the
rows as a single `text!` with no color attribute of its own, so they take
the theme's text color together or not at all. Under a theme whose text is
a mid gray -- `dark` and `light` both are -- that row reads badly, as it
does in stock Makie. Giving `Menu` an accent of its own would fix it and
break the agreement with the sliders and buttons beside it, which is the
worse trade.
"""
function block_theme(colors::ThemeColors)::Attributes
    face = colors.widget_face
    Theme(
        Menu = (
            selection_cell_color_inactive = opaque(face),
            cell_color_inactive_even = opaque(colors.menu_cell),
            cell_color_inactive_odd = opaque(colors.menu_cell),
            dropdown_arrow_color = colors.dropdown_arrow,
            textcolor = readable_on(colors, face),
        ),
        Button = (
            buttoncolor = opaque(face),
            labelcolor = readable_on(colors, face),
            labelcolor_hover = contrast_pole(colors.accent_dimmed),
            labelcolor_active = contrast_pole(colors.accent),
        ),
        Toggle = (framecolor_inactive = opaque(face),),
        Slider = (color_inactive = opaque(face),),
    )
end

end # module
