module Plotting

using DataStructures
using Printf
using Makie
using GLMakie
using GeoMakie
using Suppressor

import ..Constants
import ..RescaleUnits
import ..Interpolate
import ..Data
import ..DataLimits
import ..UI
import ..Parsing

# ============================================================
#  Plot types and their properties
# ============================================================

struct Plot
    type::String
    ndims::Int
    colorbar::Bool
    func::Function
    make_axis::Function
    # how many data components the type draws: one for a scalar field,
    # two for the vector types, which take a zonal and a meridional one
    nfields::Int
    # which kind of axis the type needs (:none for "nothing selected").
    # Overlaid layers share one axis, so only types agreeing on this *and*
    # on `ndims` can be drawn on top of one another.
    axis_kind::Symbol

    Plot(type::String, ndims::Int, colorbar::Bool, func::Function,
         make_axis::Function; nfields::Int = 1, axis_kind::Symbol = :ax2d) =
        new(type, ndims, colorbar, func, make_axis, nfields, axis_kind)
end

const PLOT_TYPES = OrderedDict(plot.type => plot for plot in [
    Plot(Constants.NOT_SELECTED_LABEL, 0, false,
        (fd, ax, i, x, y, z, d) -> nothing,
        (fd) -> nothing; axis_kind = :none),
])

function get_plot_options(ndims::Int)::Vector{String}
    if ndims >= 3
        collect(keys(PLOT_TYPES))
    elseif ndims == 2
        filter(k -> PLOT_TYPES[k].ndims ≤ 2, collect(keys(PLOT_TYPES)))
    elseif ndims == 1
        filter(k -> PLOT_TYPES[k].ndims ≤ 1, collect(keys(PLOT_TYPES)))
    else
        [Constants.NOT_SELECTED_LABEL]
    end
end

function get_fallback_plot(ndims::Int)::String
    if ndims >= 2
        Constants.PLOT_DEFAULT_2D
    elseif ndims == 1
        Constants.PLOT_DEFAULT_1D
    else
        Constants.NOT_SELECTED_LABEL
    end
end

function get_dimension_plot(ndims::Int)::String
    if ndims >= 3
        Constants.PLOT_DEFAULT_3D
    elseif ndims == 2
        Constants.PLOT_DEFAULT_2D
    elseif ndims == 1
        Constants.PLOT_DEFAULT_1D
    else
        Constants.NOT_SELECTED_LABEL
    end
end

# ------------------------------------------------------------
#  Overlaid layers: naming and compatibility
# ------------------------------------------------------------
#
# A figure draws one or more layers on a single axis. Layer 1 is the base
# and is authoritative: it fixes the dimensions, the axis, the labels and
# the title, and it owns the colorbar. Every further layer has to agree
# with it on both the number of drawn dimensions and the kind of axis, and
# sits at the same index of every sliced dimension.

"Whether `plot` can be drawn on the same axis as the base type `base`."
fits_layer(base::Plot, plot::Plot)::Bool =
    base.axis_kind !== :none && base.ndims == plot.ndims &&
    base.axis_kind === plot.axis_kind

"The plot types an overlay of `base` may be drawn with."
overlay_plot_options(base::Plot)::Vector{String} =
    [name for (name, plot) in PLOT_TYPES if fits_layer(base, plot)]

"""
    default_overlay_plot(base, nvars)

The type a new overlay starts out with: a vector type when two variables
were named, `contour` over a flat 2D base -- a second heatmap would simply
hide the first -- and the base's own type otherwise.
"""
function default_overlay_plot(base::Plot, nvars::Int)::String
    options = overlay_plot_options(base)
    nvars >= 2 && "quiver" ∈ options && return "quiver"
    "contour" ∈ options && return "contour"
    base.type
end

"The word naming layer `i` in a command and in a keyword prefix."
layer_prefix(i::Int)::String =
    i == 1 ? "base" : i == 2 ? "over" : "over$(i - 1)"

"The layer a word names, or nothing when it names no layer at all."
function layer_index(name::AbstractString)::Union{Nothing, Int}
    name == "base" && return 1
    name == "over" && return 2
    m = match(r"^over([0-9]+)$", name)
    m === nothing && return nothing
    n = parse(Int, m.captures[1])
    n < 1 ? nothing : n + 1
end

"""
    split_layer_key(key)

A keyword written as `over.levels` or `base.colormap`, split into the
layer it addresses and the property left over -- nothing when it carries
no such prefix.
"""
function split_layer_key(key::Symbol)::Union{Nothing, Tuple{Int, Symbol}}
    s = String(key)
    dot = findfirst('.', s)
    dot === nothing && return nothing
    i = layer_index(SubString(s, 1, dot - 1))
    i === nothing && return nothing
    rest = SubString(s, dot + 1)
    isempty(rest) && return nothing
    (i, Symbol(rest))
end

# ============================================================
#  Figure Settings
# ============================================================

struct FigureSettings
    figsize::Observable{Tuple{Int, Int}}
    cbar::Observable{Bool}
    moveable::Observable{Union{Bool, Nothing}}  # limits the interactivity of the axis
    geographic::Observable{Bool}
    proj::Observable{Union{String, Nothing}}
    coastlines::Observable{Bool}
    land::Observable{Bool}
    earth::Observable{Bool}
    scale::Observable{Int}
    # Label showing the current value of the sliced/animated axes.
    animlabel::Observable{Union{Bool, String}}
    animlabelpos::Observable{Symbol}
    animlabelnumfmt::Observable{String}
    animlabeldateformat::Observable{String}
    animlabelcorner::Observable{Symbol}
    animlabelbg::Observable{Any}
    # Display unit of the playback dimension in the animated-axis label
    # (nothing = native, "auto" = derived from the axis magnitude)
    animunit::Observable{Union{Nothing, String}}
    # nothing = automatic (the variable label); a string overrides it
    title::Observable{Union{Nothing, String}}
    titlesize::Observable{Float64}
    animlabelsize::Observable{Float64}
    # Colorbar label: nothing = none (the default), "auto"/true = the
    # variable's own label, false/"" = explicitly off, any other string
    # is drawn literally. The rest style it.
    cbarlabel::Observable{Union{Nothing, Bool, String}}
    cbarlabelsize::Observable{Float64}
    cbarlabelcolor::Observable{Any}
    cbarlabelfont::Observable{String}
    # nothing = Makie's automatic orientation; a number is radians
    cbarlabelrotation::Observable{Union{Nothing, Float64}}
    cbarlabelpadding::Observable{Float64}
    # Display unit per axis (nothing = native); tick rendering only
    xunit::Observable{Union{Nothing, String}}
    yunit::Observable{Union{Nothing, String}}
    zunit::Observable{Union{Nothing, String}}
    # Axis3 camera rotation in degrees per second (0 = off); the
    # vertical rotation bounces between the elevation limits
    rotate::Observable{Float64}
    rotatev::Observable{Float64}
    # Rotation bounds in degrees: azimuth sector (nothing = full orbit)
    # and elevation bounce range
    rotatelim::Observable{Union{Nothing, NTuple{2, Float64}}}
    rotatevlim::Observable{NTuple{2, Float64}}
    # Vector-plot density: how many arrows to aim for along each axis, and
    # an exact grid stride that overrides that target when set
    arrows::Observable{Tuple{Int, Int}}
    every::Observable{Union{Nothing, Int}}

    FigureSettings() = new(
        Observable(Constants.FIGSIZE),
        Observable(true),         # colorbar
        Observable(nothing),      # moveable
        Observable(false),        # geographic
        Observable(nothing),      # projection
        Observable(true),         # coastlines
        Observable(false),        # land
        Observable(false),        # earth
        Observable(110),          # scale
        Observable{Union{Bool, String}}(true),          # animlabel
        Observable(Constants.ANIMLABEL_POSITION),       # animlabelpos
        Observable(Constants.ANIMLABEL_NUMFMT),        # animlabelnumfmt
        Observable(Constants.DATETIME_FORMAT),          # animlabeldateformat
        Observable(Constants.ANIMLABEL_CORNER),         # animlabelcorner
        Observable{Any}(Constants.ANIMLABEL_BACKGROUND),  # animlabelbg
        Observable{Union{Nothing, String}}(nothing),      # animunit
        Observable{Union{Nothing, String}}(nothing),      # title override
        Observable(Float64(Constants.TITLESIZE)),         # titlesize
        Observable(Float64(Constants.LABELSIZE)),         # animlabelsize
        Observable{Union{Nothing, Bool, String}}(nothing),  # cbarlabel
        Observable(Float64(Constants.LABELSIZE)),         # cbarlabelsize
        Observable{Any}(Constants.CBARLABEL_COLOR),       # cbarlabelcolor
        Observable(Constants.CBARLABEL_FONT),             # cbarlabelfont
        Observable{Union{Nothing, Float64}}(nothing),     # cbarlabelrotation
        Observable(Float64(Constants.CBARLABEL_PADDING)),  # cbarlabelpadding
        Observable{Union{Nothing, String}}(nothing),      # xunit
        Observable{Union{Nothing, String}}(nothing),      # yunit
        Observable{Union{Nothing, String}}(nothing),      # zunit
        Observable(0.0),                                  # rotate
        Observable(0.0),                                  # rotatev
        Observable{Union{Nothing, NTuple{2, Float64}}}(nothing),  # rotatelim
        Observable((0.0, 80.0)),                          # rotatevlim
        Observable(Constants.VECTOR_ARROWS),              # arrows
        Observable{Union{Nothing, Int}}(nothing),         # every
    )
end

# ============================================================
#  Figure labels
# ============================================================

struct FigureLabels
    title::Observable{String}
    # what `cbarlabel="auto"` shows -- the same as the title for a scalar
    # plot, but a vector plot's bar carries the magnitude, not the field
    cbar::Observable{String}
    xlabel::Observable{String}
    ylabel::Observable{String}
    zlabel::Observable{String}
end

"""
    auto_title(dataset, variable, partner, nfields)

The name a plot gives itself: the variable's label, or -- for a vector
plot, which draws two components -- both of them.
"""
auto_title(dataset::Data.CDFDataset, variable::String, partner::String,
           nfields::Int)::String =
    nfields < 2 ? Data.get_label(dataset, variable) :
        Data.get_vector_label(dataset, variable, partner)

"""
    auto_cbarlabel(dataset, variable, partner, nfields)

What `cbarlabel="auto"` shows. It deliberately differs from the title for
a vector plot: the title names the field, the bar names the scalar the
colors actually stand for, which is the magnitude.
"""
auto_cbarlabel(dataset::Data.CDFDataset, variable::String, partner::String,
               nfields::Int)::String =
    nfields < 2 ? Data.get_label(dataset, variable) :
        Data.get_magnitude_label(dataset, variable, partner)

"""
    layer_title(dataset, variable, partner, nfields)

One layer's share of a title that names several of them: the variable's
display name, or -- for a vector layer -- the magnitude its colors stand
for. The units are left off. Several of them on one line drive
`fit_title_size` straight into its floor, and the colorbar still names the
base layer's own unit.
"""
layer_title(dataset::Data.CDFDataset, variable::String, partner::String,
            nfields::Int)::String =
    nfields < 2 ? Data.get_display_name(dataset, variable) :
        Data.get_magnitude_label(dataset, variable, partner; unit = false)

function FigureLabels(ui_state::UI.State, dataset::Data.CDFDataset,
                      settings::FigureSettings)::FigureLabels
    nfields = @lift(PLOT_TYPES[$(ui_state.plot_type_name)].nfields)
    # the title is composed from every layer, so it is written by
    # `refresh_title!` instead of being lifted off the base layer alone
    title = Observable("")
    cbar = @lift(auto_cbarlabel(dataset, $(ui_state.variable),
                                $(ui_state.variable2), $nfields))
    xlabel = @lift(Data.get_label(dataset, $(ui_state.x_name);
                                  target_unit = $(settings.xunit)))
    ylabel = @lift(Data.get_label(dataset, $(ui_state.y_name);
                                  target_unit = $(settings.yunit)))
    zlabel = @lift(Data.get_label(dataset, $(ui_state.z_name);
                                  target_unit = $(settings.zunit)))
    FigureLabels(title, cbar, xlabel, ylabel, zlabel)
end

# ============================================================
#  Colorbar label
# ============================================================
#
# The colorbar is rebuilt on every redraw and on every plot type change,
# and each rebuild hands these observables to Makie, which drops its
# connections again when the bar is deleted. They are therefore derived
# once per figure: a fresh `@lift` per rebuild would leave a listener on
# the settings behind.

"The settings' colorbar label, in the shape Makie's attributes want."
struct ColorbarLabel
    text::Observable{String}
    rotation::Observable{Any}
    # the loaded font rather than its name: Makie types the text plot's
    # font input from the first value it sees, so handing it a symbol
    # once and a string later throws inside the compute graph
    font::Observable{Makie.NativeFont}
end

# the font names the figure theme carries; anything else is a font
# family name or a font file
const FONT_ALIASES = (:regular, :bold, :italic, :bolditalic)

"""
The label text: `nothing` and `false` mean none, `"auto"` (or `true`)
takes the variable's own label, and anything else is drawn literally.
"""
resolve_cbarlabel(label::Union{Nothing, Bool, AbstractString},
                  auto::AbstractString)::String =
    label === nothing || label === false ? "" :
    label === true || label == "auto" ? auto : String(label)

"Load a font by one of the theme's names, or by family name or path."
resolve_font(fonts::Attributes, name::AbstractString)::Makie.NativeFont =
    Symbol(name) in FONT_ALIASES ? to_font(fonts, Symbol(name)) :
    to_font(String(name))

function ColorbarLabel(settings::FigureSettings, labels::FigureLabels,
                       fonts::Attributes)::ColorbarLabel
    # "auto" follows the labels' own colorbar observable, so the label
    # tracks the variable instead of snapshotting its name
    text = @lift(resolve_cbarlabel($(settings.cbarlabel), $(labels.cbar)))
    rotation = Observable{Any}(Makie.automatic)
    map!(rotation, settings.cbarlabelrotation) do value
        value === nothing ? Makie.automatic : value
    end
    font = Observable{Makie.NativeFont}(
        resolve_font(fonts, Constants.CBARLABEL_FONT))
    map!(font, settings.cbarlabelfont) do value
        resolve_font(fonts, value)
    end
    ColorbarLabel(text, rotation, font)
end

# ============================================================
#  Animated-axis label segments
# ============================================================
#
# The label naming the current value of the playback dimension is not one
# string: its template is compiled into a sequence of segments -- static
# text and dynamic value slots. Each varying number lives in its own
# fixed-width slot, sized to the widest value the axis can produce
# (pixel-measured in the actual font), so nothing moves between animation
# frames: the static text around a slot is pinned, and the value grows
# leftward into its slot (right-aligned). Placeholders that cannot change
# during playback ({name}, {unit}) are substituted up front.

"One compiled piece of the label: static text, or a right-aligned slot."
struct AnimSegment
    template::String   # the placeholder ("{value}") for a slot; "" otherwise
    dynamic::Bool
    text::String       # the static text, or the slot's widest rendering
    width::Float64     # measured pixel width (the slot width for a slot)
end

# the placeholders that change from frame to frame
const ANIM_DYNAMIC_PLACEHOLDER = r"\{(?:value|rawvalue|index|duration)\}"

"""
Resolved per-axis rendering state of the animated-axis label, derived
once per recompile so the per-frame path only formats: the concrete
number format ("auto" resolved against the *displayed* values), the
concrete display unit ("auto" resolved against the axis magnitude,
nothing = native), and the shape of a `{duration}` rendering (nothing
when the axis is not a time span).
"""
struct AnimLabelConfig
    numfmt::String
    dateformat::String
    unit::Union{Nothing, String}
    durspec::Union{Nothing, Data.DurationSpec}
end

AnimLabelConfig(numfmt::AbstractString, dateformat::AbstractString) =
    AnimLabelConfig(String(numfmt), String(dateformat), nothing, nothing)

"The template in `animlabel`, or `\"\"` when the label is switched off."
function animlabel_format(animlabel::Union{Bool, String})::String
    animlabel === false && return ""
    animlabel isa AbstractString ? String(animlabel) : Constants.ANIMLABEL_FORMAT
end

"The font the animated-axis label renders in (the theme's regular font)."
function animlabel_font()
    try
        Makie.to_font(Makie.to_value(Makie.theme(:fonts).regular))
    catch
        Makie.to_font("TeX Gyre Heros Makie")
    end
end

"The font the header title renders in (the theme's bold font)."
function title_font()
    try
        Makie.to_font(Makie.to_value(Makie.theme(:fonts).bold))
    catch
        Makie.to_font("TeX Gyre Heros Makie")
    end
end

"Measured pixel width of `s` at the given fontsize, in the given font."
measure_text(s::String, fontsize::Real = Constants.LABELSIZE,
             font = animlabel_font())::Float64 =
    isempty(s) ? 0.0 : Float64(Makie.widths(
        Makie.text_bb(s, font, Float64(fontsize)))[1])

"Measured pixel height of `s` at the given fontsize."
measure_height(s::String, fontsize::Real = Constants.LABELSIZE)::Float64 =
    Float64(Makie.widths(Makie.text_bb(isempty(s) ? "Ag" : s, animlabel_font(),
                                       Float64(fontsize)))[2])

"Render one dynamic placeholder for the current index."
render_slot(dataset::Data.CDFDataset, pdim::String, idx::Int,
            placeholder::String, config::AnimLabelConfig)::String =
    Data.format_dim_label(dataset, pdim, idx; fmt = placeholder,
                          numfmt = config.numfmt,
                          dateformat = config.dateformat,
                          target_unit = config.unit,
                          durspec = config.durspec)

"""
    widest_slot_text(dataset, pdim, placeholder, config)

The widest rendering a placeholder can produce over the whole axis
(pixel-measured; long axes are sampled). The slot is sized from it, so the
slot never changes width during playback.
"""
function widest_slot_text(
    dataset::Data.CDFDataset, pdim::String, placeholder::String,
    config::AnimLabelConfig,
    fontsize::Real = Constants.LABELSIZE,
)::String
    n = try
        length(Data.get_dim_values(dataset, pdim))
    catch
        return ""
    end
    n <= 0 && return ""
    idxs = n <= Constants.ANIMLABEL_WIDTH_SAMPLES ? (1:n) :
        round.(Int, range(1, n; length = Constants.ANIMLABEL_WIDTH_SAMPLES))
    widest, wmax = "", -1.0
    for i in idxs
        s = render_slot(dataset, pdim, i, placeholder, config)
        w = measure_text(s, fontsize)
        w > wmax && (widest = s; wmax = w)
    end
    widest
end

"Smallest decimal count that reproduces `x` to ~1e-4 relative error."
function repr_decimals(x::Float64)::Int
    for d in 0:10
        abs(x - round(x; digits = d)) <= abs(x) * 1e-4 && return d
    end
    6
end

"""
    uniform_numfmt(values)

One printf spec that renders every value of an axis with the same number
of digits, derived from the axis step and magnitude: fixed decimals for
ordinary ranges ("0.5" -> "1.0" -> "1.5"), scientific with mantissa
digits from the step otherwise ("1.5e-05" -> "1.6e-05"). Uniform widths
keep a right-aligned value from dancing inside its slot.
"""
function uniform_numfmt(values)::String
    vals = Float64[Float64(v) for v in values
                   if v isa Number && isfinite(v)]
    isempty(vals) && return Constants.NUMBER_FORMAT
    magnitude = maximum(abs, vals)
    magnitude == 0 && return "%.0f"
    steps = [abs(vals[i + 1] - vals[i]) for i in 1:(length(vals) - 1)]
    filter!(>(0.0), steps)
    step = isempty(steps) ? magnitude : minimum(steps)
    if step >= 1e-4 && magnitude < 1e7
        return "%.$(repr_decimals(step))f"
    end
    # mantissa step relative to the leading decade
    mantissa_step = step / exp10(floor(log10(magnitude)))
    "%.$(min(repr_decimals(mantissa_step), 6))e"
end

"The concrete number format: the user's spec, or derived from the axis."
function resolve_numfmt(
    dataset::Data.CDFDataset, pdim::String, numfmt::String,
)::String
    numfmt == "auto" || return numfmt
    values = try
        Data.get_dim_values(dataset, pdim)
    catch
        return Constants.NUMBER_FORMAT
    end
    uniform_numfmt(values)
end

"""
    resolve_animunit(dataset, pdim, setting, values)

The concrete display unit of the playback dimension, or nothing (native):
"auto" picks the family unit fitting the axis magnitude; an explicit unit
applies only when the native unit converts into it.
"""
function resolve_animunit(
    dataset::Data.CDFDataset, pdim::String,
    setting::Union{Nothing, String}, values::Vector{Float64},
)::Union{Nothing, String}
    setting === nothing && return nothing
    pdim ∈ keys(dataset.ds) || return nothing
    native = RescaleUnits.get_unit(dataset.ds, pdim)
    if setting == "auto"
        magnitude = maximum(abs, filter(isfinite, values); init = 0.0)
        return RescaleUnits.auto_display_unit(native, magnitude)
    end
    RescaleUnits.display_factor(native, setting) === nothing ? nothing : setting
end

"""
    resolve_anim_config(dataset, pdim, settings)

Resolve the label's per-axis rendering state in dependency order: the
display unit first, then the number format from the *converted* values
(so "auto" digit counts fit what is actually shown), and the duration
shape from the axis in seconds.
"""
function resolve_anim_config(
    dataset::Data.CDFDataset, pdim::String, settings::FigureSettings,
)::AnimLabelConfig
    values = try
        Data.get_dim_values(dataset, pdim)
    catch
        Float64[]
    end
    unit = resolve_animunit(dataset, pdim, settings.animunit[], values)
    factor = Data.dim_unit_factor(dataset, pdim, unit)
    displayed = factor === nothing ? values : values .* factor
    numfmt = settings.animlabelnumfmt[] != "auto" ?
        settings.animlabelnumfmt[] :
        isempty(displayed) ? String(Constants.NUMBER_FORMAT) :
        uniform_numfmt(displayed)
    seconds_factor = Data.dim_unit_factor(dataset, pdim, "s")
    durspec = seconds_factor === nothing || isempty(values) ? nothing :
        Data.derive_duration_spec(values .* seconds_factor)
    AnimLabelConfig(numfmt, settings.animlabeldateformat[], unit, durspec)
end

"""
    compile_animlabel(dataset, variable, sel_dims, pdim, animlabel,
                      config)

Compile the label template into its segment sequence, or `[]` when no
label applies: the label is off, no playback dimension is selected, the
playback dimension is drawn as a plot axis, or the variable lacks it.
"""
function compile_animlabel(
    dataset::Data.CDFDataset,
    variable::String,
    sel_dims::Vector{String},
    pdim::String,
    animlabel::Union{Bool, String},
    config::AnimLabelConfig,
    fontsize::Real = Constants.LABELSIZE,
)::Vector{AnimSegment}
    fmt = animlabel_format(animlabel)
    isempty(fmt) && return AnimSegment[]
    pdim == Constants.NOT_SELECTED_LABEL && return AnimSegment[]
    pdim ∈ sel_dims && return AnimSegment[]
    haskey(dataset.var_coords, variable) || return AnimSegment[]
    pdim ∈ Data.get_var_dims(dataset, variable) || return AnimSegment[]
    # a duration slot on a non-time-span axis degrades to a value slot, so
    # one template stays valid while the playback dimension changes
    config.durspec === nothing && (fmt = replace(fmt, "{duration}" => "{value}"))
    # placeholders that cannot change during playback become static text
    fmt = replace(fmt,
        "{name}" => Data.get_dim_display_name(dataset, pdim),
        "{unit}" => Data.get_dim_display_unit(dataset, pdim, config.unit))
    static(txt) = AnimSegment("", false, txt, measure_text(txt, fontsize))
    segments = AnimSegment[]
    pos = 1
    for m in eachmatch(ANIM_DYNAMIC_PLACEHOLDER, fmt)
        m.offset > pos &&
            push!(segments, static(fmt[pos:prevind(fmt, m.offset)]))
        widest = widest_slot_text(dataset, pdim, String(m.match),
                                  config, fontsize)
        push!(segments, AnimSegment(String(m.match), true, widest,
                                    measure_text(widest, fontsize)))
        pos = m.offset + ncodeunits(m.match)
    end
    pos <= ncodeunits(fmt) && push!(segments, static(fmt[pos:end]))
    segments
end

# ============================================================
#  Plot data
# ============================================================

"""
    partner_data(dataset, variable, partner, sel_dims, selection)

The second component's data, or nothing when no usable partner is
selected. A partner that does not span the same dimensions cannot be
sliced by the same indexing, so it yields nothing and the vector plot
simply draws nothing until a fitting one is picked.
"""
function partner_data(dataset::Data.CDFDataset, variable::String,
                      partner::String, sel_dims::Vector{String},
                      selection::Dict{String, Int})::Union{Array, Nothing}
    Data.is_vector_partner(dataset, variable, partner) || return nothing
    Data.get_data(dataset, partner, sel_dims, selection)
end

"""
One layer's own state: the variable(s) it draws and the type it draws them
with. Layer 1's observables are the menu's own, so the GUI keeps driving
the base field; every further layer carries its own.
"""
struct DataLayer
    variable::Observable{String}
    variable2::Observable{String}
    plot_type::Observable{Plot}
end

struct PlotData
    # layer 1's plot type -- the menu-driven one, which fixes the axis and
    # the dimensions every layer shares
    plot_type::Observable{Plot}
    sel_dims::Observable{Vector{String}}
    # the index every layer sits at, per sliced dimension (figure-level:
    # layers share the slice as well as the axes)
    dim_obs::Observable{Dict{String, Int}}
    x::Observable{Union{Array, Nothing}}
    y::Observable{Union{Array, Nothing}}
    z::Observable{Union{Array, Nothing}}
    # data arrays indexed [layer][component][ndims]: component 1 is the
    # layer's variable, component 2 the partner a vector plot draws next
    # to it. Grown and shrunk together with `layers`.
    d::Vector{Vector{Vector{Observable{Union{Array, Nothing}}}}}
    layers::Vector{DataLayer}
    update_data_switch::Observable{Bool}
    labels::FigureLabels
    dataset::Data.CDFDataset
    # Owned here so the labels and the FigureData share one settings object:
    # the title lifts the animated-axis label straight out of it.
    settings::FigureSettings
end

function PlotData(
    ui_state::UI.State,
    dataset::Data.CDFDataset,
    settings::FigureSettings = FigureSettings(),
)::PlotData
    # Observable for the plot_type
    plot_type = @lift(PLOT_TYPES[$(ui_state.plot_type_name)])

    # Observable for the selected dimensions
    sel_dims = @lift([$(ui_state.x_name),
                      $(ui_state.y_name),
                      $(ui_state.z_name),][1:$plot_type.ndims])

    # Observables for x, y, z dimension arrays
    update_switch = Observable(true)
    x = Data.get_dim_array(dataset, ui_state.x_name, update_switch)
    y = Data.get_dim_array(dataset, ui_state.y_name, update_switch)
    z = Data.get_dim_array(dataset, ui_state.z_name, update_switch)

    # Figure labels
    labels = FigureLabels(ui_state, dataset, settings)

    plot_data = PlotData(
        plot_type, sel_dims, ui_state.dim_obs, x, y, z,
        Vector{Vector{Observable{Union{Array, Nothing}}}}[], DataLayer[],
        update_switch, labels, dataset, settings)

    # Layer 1 draws the menu's own variable with the menu's own plot type
    push_layer!(plot_data, ui_state.variable, ui_state.variable2, plot_type)

    # Everything that moves every layer at once: the drawn axes, the slice,
    # and the switch that suspends reading while the menus reconcile
    for trigger in (sel_dims, ui_state.dim_obs, update_switch)
        on(trigger) do _
            refresh_layers_data!(plot_data)
        end
    end

    plot_data
end

"""
    push_layer!(plot_data, variable, variable2, plot_type)

Append one layer -- its state observables and its data observables -- and
wire up the listeners keeping its data and the figure title in step.
Returns the new layer's index.
"""
function push_layer!(plot_data::PlotData, variable::Observable{String},
                     variable2::Observable{String},
                     plot_type::Observable{Plot})::Int
    layer = DataLayer(variable, variable2, plot_type)
    push!(plot_data.layers, layer)
    push!(plot_data.d,
          [[Observable{Union{Array, Nothing}}(nothing) for _ in 1:3]
           for _ in 1:Constants.MAX_PLOT_COMPONENTS])
    index = length(plot_data.layers)
    # the listeners look the layer up by identity rather than closing over
    # its index: dropping a layer renumbers the ones above it, and a stale
    # listener of a dropped layer must go quiet instead of writing into
    # somebody else's slot
    locate() = findfirst(l -> l === layer, plot_data.layers)
    # layer 1's own plot type needs no trigger of its own: `sel_dims` lifts
    # off it and fires for it. An overlay's does not reach `sel_dims`.
    triggers = index == 1 ? (variable, variable2) :
        (variable, variable2, plot_type)
    for trigger in triggers
        on(trigger) do _
            i = locate()
            i === nothing || refresh_layer_data!(plot_data, i)
        end
    end
    for trigger in (variable, variable2, plot_type)
        on(trigger) do _
            refresh_title!(plot_data)
        end
    end
    refresh_title!(plot_data)
    index
end

"""
    compose_title(plot_data)

The name the figure gives itself: with a single layer the layer's own
label, exactly as before overlays existed, and with several the layers'
names joined by " / ".
"""
function compose_title(plot_data::PlotData)::String
    dataset = plot_data.dataset
    layers = plot_data.layers
    isempty(layers) && return ""
    length(layers) == 1 && return auto_title(
        dataset, layers[1].variable[], layers[1].variable2[],
        layers[1].plot_type[].nfields)
    join((layer_title(dataset, l.variable[], l.variable2[],
                      l.plot_type[].nfields) for l in layers), " / ")
end

"Recompute the figure title from the layers currently drawn."
function refresh_title!(plot_data::PlotData)::Nothing
    plot_data.labels.title[] = compose_title(plot_data)
    nothing
end

"""
    layer_fits_axes(plot_data, variable)

Whether a layer drawing `variable` can be sliced onto the drawn axes.
Every plot dimension has to be one of the variable's own; the sliced ones
need not be, since `Data.get_indexing` walks the variable's dimensions and
ignores the rest of the selection.
"""
function layer_fits_axes(plot_data::PlotData, variable::String)::Bool
    haskey(plot_data.dataset.var_coords, variable) || return false
    dims = Data.get_var_dims(plot_data.dataset, variable)
    all(dim -> dim ∈ dims, plot_data.sel_dims[])
end

"Re-read one layer's data for the current axes and slice."
function refresh_layer_data!(plot_data::PlotData, i::Int)::Nothing
    plot_data.update_data_switch[] || return nothing
    sel_dims = plot_data.sel_dims[]
    ndims = length(sel_dims)
    ndims == 0 && return nothing
    layer = plot_data.layers[i]
    variable = layer.variable[]
    # a layer whose variable does not span the drawn axes cannot be sliced
    # by them; the menus are mid-reconcile, or the layer is about to be
    # dropped, so leave what it holds alone
    layer_fits_axes(plot_data, variable) || return nothing
    dataset = plot_data.dataset
    selection = plot_data.dim_obs[]
    plot_data.d[i][1][ndims][] =
        Data.get_data(dataset, variable, sel_dims, selection)
    # the partner is only read when a plot type asks for it: a scalar type
    # must never pay for a second hyperslab read
    layer.plot_type[].nfields < 2 && return nothing
    plot_data.d[i][2][ndims][] = partner_data(
        dataset, variable, layer.variable2[], sel_dims, selection)
    nothing
end

"Re-read every layer's data."
function refresh_layers_data!(plot_data::PlotData)::Nothing
    for i in eachindex(plot_data.layers)
        refresh_layer_data!(plot_data, i)
    end
    nothing
end

# ============================================================
#  Pinned color range
# ============================================================
#
# Makie derives an unset colorrange from the data of the current frame,
# so playback rescales the colors on every step. The scanner pins the
# range to the extrema of everything the animation can show instead:
# with a playback dimension selected, a background task scans the
# variable's native hyperslab over the whole playback axis (other sliced
# dimensions stay fixed) and applies the result once -- colors and
# colorbar hold still while the data moves. The mode comes through the
# `colorrange` keyword: a (lo, hi) tuple pins manually, "cycle" (the
# default) pins to the playback cycle, "data" to the whole variable, and
# "frame" restores Makie's per-frame autoscaling.

const CRANGE_MODES = ("cycle", "frame", "data")

"""
Mutable scan state: what is pinned, what is in flight, and past results.
One per layer -- each draws its own field and pins its own range. The
size-gate hint is not here but on the figure: it is shown once, not once
per layer.
"""
mutable struct ColorRangeScan
    generation::Int                   # bumped to abort superseded scans
    pending_key::Any                  # key of the scan in flight
    applied_key::Any                  # key of the currently applied pin
    task::Union{Nothing, Task}
    cache::Dict{Any, NTuple{2, Float64}}
    base_levels::Union{Nothing, Int}  # the plot's own Int `levels`
end

ColorRangeScan() = ColorRangeScan(0, nothing, nothing, nothing,
                                  Dict{Any, NTuple{2, Float64}}(), nothing)

# ============================================================
#  Figure data structure
# ============================================================

"""
The figure settings one layer may differ in. Only the vector-plot density
so far: two quiver layers on one axis at the same arrow count are
unreadable, so `over2.arrows` has to reach that layer's arrows rather than
every set of arrows on the figure. `nothing` means "whatever the figure
says", which is what a plain `arrows=` sets.
"""
mutable struct LayerSettings
    arrows::Union{Nothing, Tuple{Int, Int}}
    every::Union{Nothing, Int}
end

LayerSettings() = LayerSettings(nothing, nothing)

"""
One drawn layer: the plot object sitting on the axis, the settings it
differs from the figure in, and the color-range scan pinning its colors.
Runs parallel to `PlotData.layers`, which holds the same layer's data.
"""
struct Layer
    plot_obj::Observable{Union{Makie.AbstractPlot, Nothing}}
    settings::LayerSettings
    crange_scan::ColorRangeScan
end

Layer() = Layer(Observable{Union{Makie.AbstractPlot, Nothing}}(nothing),
                LayerSettings(), ColorRangeScan())

struct FigureData
    fig::Figure
    plot_data::PlotData
    ax::Observable{Union{Makie.AbstractAxis, Nothing}}
    layers::Vector{Layer}
    cbar::Observable{Union{Colorbar, Nothing}}
    land::Observable{Union{Makie.AbstractPlot, Nothing}}
    coastlines::Observable{Union{Makie.AbstractPlot, Nothing}}
    earth::Observable{Union{Makie.AbstractPlot, Nothing}}
    data_inspector::Observable{Union{DataInspector, Nothing}}
    tasks::Observable{Vector{Task}}
    settings::FigureSettings
    range_control::Observable{Interpolate.RangeControl}
    ui::UI.UIElements
    # scene-anchored header: the resolved title text + its drawn plots
    title_text::Observable{String}
    anim_header::Base.RefValue{Vector{Any}}
    anim_slots::Vector{Observable{String}}
    anim_segments::Base.RefValue{Vector{AnimSegment}}
    anim_overlay::Base.RefValue{Vector{Any}}
    # the label's resolved rendering state (numfmt/unit/duration shape)
    anim_config::Base.RefValue{AnimLabelConfig}
    # the color-range size gate has already explained itself once
    crange_hinted::Base.RefValue{Bool}
    # +1/-1: which way the bouncing camera rotations are heading
    camera_vdir::Base.RefValue{Float64}
    camera_hdir::Base.RefValue{Float64}
    # what every rebuilt colorbar hands to Makie as its label
    cbar_label::ColorbarLabel
end

function FigureData(plot_data::PlotData, ui::UI.UIElements)::FigureData
    ui_state = ui.state
    # one settings object, shared with the labels that lift out of it
    settings = plot_data.settings
    # Create axis, plot object, and colorbar observables
    figsize = Observable(Constants.FIGSIZE)
    fig = create_figure(figsize[])
    # Row 1 is only a spacer: the header itself (title left, animated
    # label right) is drawn scene-anchored to the axis' plot box, so it
    # hugs an aspect-letterboxed plot instead of leaving a band of
    # whitespace under a figure-top title (a letterboxed axis floats
    # centred in its cell -- block valign cannot reach it). The spacer
    # keeps the band reserved for an axis that fills its whole cell. The
    # native axis title stays disabled (Axis3 clips multi-line titles).
    title_text = @lift begin
        override = $(settings.title)
        override === nothing ? $(plot_data.labels.title) : override
    end
    header_height = @lift(Constants.HEADER_GAP + 4 +
        measure_height("Ag", max($(settings.titlesize),
                                 $(settings.animlabelsize))))
    Box(fig[1, 1]; visible = false, height = header_height,
        tellheight = true, tellwidth = false)
    ax = Observable{Union{Makie.AbstractAxis, Nothing}}(nothing)
    # one drawn layer per layer of the plot data; layer 1 is the base
    layers = [Layer() for _ in plot_data.layers]
    cbar = Observable{Union{Colorbar, Nothing}}(nothing)
    land = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    coastlines = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    earth = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    data_inspector = Observable{Union{DataInspector, Nothing}}(nothing)

    # Construct the FigureData
    fd = FigureData(
        fig,
        plot_data,
        ax,
        layers,
        cbar,
        data_inspector,
        land,
        coastlines,
        earth,
        Observable(Task[]),
        settings,
        ui_state.range_control,
        ui,
        title_text,
        Ref(Any[]),
        Observable{String}[],
        Ref(AnimSegment[]),
        Ref(Any[]),
        Ref(AnimLabelConfig(Constants.NUMBER_FORMAT, Constants.DATETIME_FORMAT)),
        Ref(false),
        Ref(1.0),
        Ref(1.0),
        ColorbarLabel(settings, plot_data.labels, theme(fig.scene).fonts),
    )

    # Rebuild the animated-axis label when its configuration changes;
    # per-frame value updates only touch the slot text observables.
    for trigger in (ui_state.variable, plot_data.sel_dims, ui_state.pdim,
                    settings.animlabel, settings.animlabelnumfmt,
                    settings.animlabeldateformat, settings.animlabelpos,
                    settings.animlabelcorner, settings.animlabelbg,
                    settings.animlabelsize, settings.animunit)
        on(trigger) do _
            update_animlabel!(fd)
        end
    end
    on(ui_state.dim_obs) do _
        refresh_anim_values!(fd)
    end
    update_animlabel!(fd)

    # Keep the pinned color range reconciled; during playback only the
    # playback index changes, which leaves the scan key untouched.
    for trigger in (ui_state.variable, ui_state.variable2, plot_data.sel_dims,
                    ui_state.pdim, ui_state.dim_obs)
        on(trigger) do _
            update_colorrange!(fd)
        end
    end

    # Setup a listener to create the plots if the axis changes.
    #
    # Every layer is built from here, and only from here. `redraw!` swaps
    # the axis identity, and a layer built anywhere else would stay
    # parented to the axis that has just been deleted -- it would simply
    # vanish from the figure with nothing to show for it.
    on(ax) do a
        a === nothing && return
        # first we clear the previous plots (a fresh axis carries none; a
        # notify() to rebuild in place does)
        clear_layer_plots!(fd)
        cbar[] !== nothing && delete!(cbar[])
        cbar[] = nothing
        plot_data.plot_type[].type == Constants.NOT_SELECTED_LABEL && return  # TODO

        # then we create the new plots, one per layer, handing each one
        # data observable per component its type draws
        build_layer_plots!(fd, a)
        # and add a colorbar if needed -- one for the whole figure, the
        # base layer's
        add_colorbar!(fd)
        add_earth!(fd)
        add_land!(fd)
        add_coastlines!(fd)
        rebuild_header!(fd)
        rebuild_overlay!(fd)
        refresh_anim_values!(fd)
        apply_kwargs!(fd, ui_state.kwargs[])
        update_colorrange!(fd)
    end

    # Setup listeners to apply axis and plot keyword arguments
    on(ui.main_menu.plot_menu.plot_kw.stored_string) do kw_str
        on_kwarg_string_update(fd, kw_str)
    end

    # return the FigureData
    fd
end

# ============================================================
#  Overlaid layers
# ============================================================
#
# The layers are two parallel vectors: `PlotData.layers` holds what a
# layer draws, `FigureData.layers` what it has drawn. They are only ever
# grown and shrunk together, from here.

"The base layer's plot object -- the one the colorbar and the labels follow."
primary(fd::FigureData)::Union{Makie.AbstractPlot, Nothing} =
    fd.layers[1].plot_obj[]

"How many fields the figure draws on top of each other."
layer_count(fd::FigureData)::Int = length(fd.layers)

"The type layer `i` draws with."
layer_plot(fd::FigureData, i::Int)::Plot = fd.plot_data.layers[i].plot_type[]

"Every variable layer `i` names, in component order."
function layer_variables(fd::FigureData, i::Int)::Vector{String}
    layer = fd.plot_data.layers[i]
    variables = [layer.variable[]]
    layer.plot_type[].nfields < 2 && return variables
    partner = layer.variable2[]
    Data.is_vector_partner(fd.plot_data.dataset, variables[1], partner) &&
        push!(variables, partner)
    variables
end

"Wait for every layer's color-range scan to finish."
function wait_for_scans(fd::FigureData)::Nothing
    for layer in fd.layers
        task = layer.crange_scan.task
        task === nothing || wait(task)
    end
    nothing
end

"""
    clear_layer_plots!(fd)

Take every layer's plot off the axis. Rebuilding in place (a `notify` on
the axis, after a layer was added or dropped) would otherwise leave the
previous plots drawn underneath the new ones.
"""
function clear_layer_plots!(fd::FigureData)::Nothing
    ax = fd.ax[]
    for layer in fd.layers
        plot = layer.plot_obj[]
        plot === nothing && continue
        # a plot of an axis that has already been deleted is gone with it;
        # only the bookkeeping is left to do
        ax === nothing || try
            delete!(ax, plot)
        catch
        end
        layer.plot_obj[] = nothing
    end
    nothing
end

"""
    lift_overlay!(obj, i)

Put overlay `i` in front of the layers below it. Two mechanisms, because
one is not enough: a step in z orders flat plots that all sit at z = 0,
and a depth shift -- which works in clip space, not data space -- handles
the case that has no scale to reason about. On a map a "heatmap" is
really a `surface!` whose z *is* the field, so it towers over any fixed
offset an overlay could be given.
"""
function lift_overlay!(obj, i::Int)::Nothing
    Makie.translate!(obj, 0, 0, Float32(i - 1))
    :depth_shift ∈ propertynames(obj) &&
        (obj.depth_shift[] = -0.01f0 * (i - 1))
    nothing
end

"""
    build_layer_plots!(fd, ax)

Draw every layer onto `ax`, base first, each in front of the one below.
The overlays are only lifted on a flat axis: on an Axis3 both the z and
the depth are the data's own.
"""
function build_layer_plots!(fd::FigureData, ax::Makie.AbstractAxis)::Nothing
    plot_data = fd.plot_data
    for (i, layer) in enumerate(fd.layers)
        plot = plot_data.layers[i].plot_type[]
        plot.type == Constants.NOT_SELECTED_LABEL && continue
        components = Tuple(plot_data.d[i][c][plot.ndims] for c in 1:plot.nfields)
        obj = plot.func(fd, ax, i, plot_data.x, plot_data.y, plot_data.z,
                        components...)
        i > 1 && plot.axis_kind === :ax2d && lift_overlay!(obj, i)
        layer.plot_obj[] = obj
        # a fresh plot carries no pin and owns its levels again
        layer.crange_scan.applied_key = nothing
        layer.crange_scan.base_levels = nothing
    end
    nothing
end

"Redraw every layer on the axis that is already there."
function rebuild_layers!(fd::FigureData)::Nothing
    fd.ax[] === nothing && return nothing
    notify(fd.ax)
    nothing
end

"""
    add_layer!(fd, variable, variable2, plot_type)

Append a layer to both halves of the state and return its index. The plot
itself is not drawn here -- `rebuild_layers!` does that once the caller
has finished configuring the layer.
"""
function add_layer!(fd::FigureData, variable::String, variable2::String,
                    plot_type::Plot)::Int
    plot_data = fd.plot_data
    index = push_layer!(plot_data, Observable(variable),
                        Observable(variable2), Observable(plot_type))
    push!(fd.layers, Layer())
    refresh_layer_data!(plot_data, index)
    layer = plot_data.layers[index]
    for trigger in (layer.variable, layer.variable2, layer.plot_type)
        on(trigger) do _
            update_colorrange!(fd)
        end
    end
    index
end

"""
    drop_layers!(fd, indices)

Remove the named layers. Removing one renumbers the layers above it, so
their keywords are renamed to follow (`over2.levels` becomes
`over.levels`) and the removed layer's own are dropped.
"""
function drop_layers!(fd::FigureData, indices::Vector{Int})::Nothing
    isempty(indices) && return nothing
    ax = fd.ax[]
    for i in sort(indices; rev = true)
        plot = fd.layers[i].plot_obj[]
        if plot !== nothing && ax !== nothing
            try
                delete!(ax, plot)
            catch
            end
        end
        deleteat!(fd.layers, i)
        deleteat!(fd.plot_data.layers, i)
        deleteat!(fd.plot_data.d, i)
    end
    rename_layer_kwargs!(fd, indices)
    refresh_title!(fd.plot_data)
    nothing
end

"""
    rename_layer_kwargs!(fd, dropped)

Follow a layer removal through the stored keywords: what the dropped
layers owned goes, what the layers above them owned moves down with them.
The store is rewritten rather than re-applied -- the layers it named are
gone, so there is nothing left to un-apply.
"""
function rename_layer_kwargs!(fd::FigureData, dropped::Vector{Int})::Nothing
    kwargs = fd.ui.state.kwargs[]
    any(key -> split_layer_key(key) !== nothing, keys(kwargs)) || return nothing
    # where each surviving layer ended up after the removal
    moved = Dict{Int, Int}()
    new_index = 0
    for old in 1:(length(fd.layers) + length(dropped))
        old ∈ dropped && continue
        new_index += 1
        moved[old] = new_index
    end
    renamed = OrderedDict{Symbol, Any}()
    for (key, value) in kwargs
        split = split_layer_key(key)
        if split === nothing
            renamed[key] = value
            continue
        end
        layer, property = split
        haskey(moved, layer) || continue  # the layer it named is gone
        renamed[Symbol(layer_prefix(moved[layer]), '.', property)] = value
    end
    keys(renamed) == keys(kwargs) && return nothing
    rewrite_kwargs!(fd, renamed)
    nothing
end

"""
    prune_layers!(fd)

Drop the overlays the base no longer supports, with a warning: the base
variable may have moved the plot onto axes an overlay's variable does not
span, or onto a different kind of axis altogether. Returns whether any
layer went.
"""
function prune_layers!(fd::FigureData)::Bool
    plot_data = fd.plot_data
    base = plot_data.plot_type[]
    # "nothing selected" is not a base a layer could disagree with; a
    # closed figure window must not cost the user their overlays
    base.type == Constants.NOT_SELECTED_LABEL && return false
    dropped = Int[]
    for i in 2:length(plot_data.layers)
        layer = plot_data.layers[i]
        name = layer_prefix(i)
        if !fits_layer(base, layer.plot_type[])
            @warn ("Dropping layer $name ($(layer.plot_type[].type)): it " *
                   "cannot be drawn on the same axis as $(base.type)")
            push!(dropped, i)
        elseif !layer_fits_axes(plot_data, layer.variable[])
            @warn ("Dropping layer $name ($(layer.variable[])): it does not " *
                   "span " * join(plot_data.sel_dims[], ", "))
            push!(dropped, i)
        end
    end
    isempty(dropped) && return false
    drop_layers!(fd, dropped)
    # the survivors moved: their plots close over the index they were
    # built at, so they have to be built again
    rebuild_layers!(fd)
    true
end

"What a layer currently draws, for a status line."
function layer_status(fd::FigureData, i::Int)::String
    i > layer_count(fd) && return "$(layer_prefix(i)) is not set."
    "$(layer_prefix(i)): " * join(layer_variables(fd, i), ", ") *
        " ($(layer_plot(fd, i).type))"
end

"""
    set_layer_variables!(fd, i, names)

Point layer `i` at the named variable(s), creating the layer when `i` is
the next one up. Returns a status line; an empty one means nothing changed
and a warning has already been issued.
"""
function set_layer_variables!(fd::FigureData, i::Int,
                              names::Vector{String})::String
    plot_data = fd.plot_data
    dataset = plot_data.dataset
    base = plot_data.plot_type[]
    if i < 2
        @warn "Layer 1 is the base field; select its variable with `v`"
        return ""
    end
    if base.type == Constants.NOT_SELECTED_LABEL
        @warn "Select a plot type before overlaying a second field"
        return ""
    end
    if i > layer_count(fd) + 1
        @warn ("Layer $(layer_prefix(i)) does not exist yet; add " *
               "$(layer_prefix(layer_count(fd) + 1)) first")
        return ""
    end
    names = filter(!isempty, names)
    if isempty(names)
        @warn "Usage: $(layer_prefix(i)) <variable>[,<partner>]"
        return ""
    end
    variable = names[1]
    if !haskey(dataset.var_coords, variable)
        @warn "Variable '$variable' not found in dataset"
        return ""
    end
    if !layer_fits_axes(plot_data, variable)
        @warn ("Variable '$variable' does not span " *
               join(plot_data.sel_dims[], ", ") *
               " and cannot be overlaid on this plot")
        return ""
    end
    existing = i <= layer_count(fd)
    current = existing ? plot_data.layers[i].plot_type[] : base
    # keep the type the layer already had, unless it no longer fits the
    # base or a second component was named that it cannot draw
    plot_type = existing && fits_layer(base, current) &&
                !(length(names) >= 2 && current.nfields < 2) ? current :
        PLOT_TYPES[default_overlay_plot(base, length(names))]
    partner = if length(names) >= 2
        names[2]
    elseif plot_type.nfields >= 2
        guess = Data.guess_vector_partner(dataset, variable)
        guess === nothing ? Constants.NOT_SELECTED_LABEL : guess
    else
        Constants.NOT_SELECTED_LABEL
    end
    if plot_type.nfields >= 2 && partner != Constants.NOT_SELECTED_LABEL &&
       !Data.is_vector_partner(dataset, variable, partner)
        @warn "Variable '$partner' cannot be a second component of '$variable'"
        return ""
    end
    if existing
        layer = plot_data.layers[i]
        # the variable last: the other two are read while it is re-sliced
        layer.variable2[] = partner
        layer.plot_type[] = plot_type
        layer.variable[] = variable
    else
        add_layer!(fd, variable, partner, plot_type)
    end
    rebuild_layers!(fd)
    layer_status(fd, i)
end

"Draw layer `i` with another plot type, if the base allows that type."
function set_layer_plot_type!(fd::FigureData, i::Int, name::String)::String
    plot_data = fd.plot_data
    if i < 2
        @warn "Layer 1 is the base field; select its plot type with `p`"
        return ""
    end
    if i > layer_count(fd)
        @warn "Layer $(layer_prefix(i)) is not set"
        return ""
    end
    options = overlay_plot_options(plot_data.plot_type[])
    if name ∉ options
        @warn ("Plot type '$name' cannot be overlaid on " *
               "$(plot_data.plot_type[].type). Available: " *
               join(options, ", "))
        return ""
    end
    layer = plot_data.layers[i]
    plot_type = PLOT_TYPES[name]
    # a vector type needs a second component; guess one from the name
    if plot_type.nfields >= 2 && !Data.is_vector_partner(
            plot_data.dataset, layer.variable[], layer.variable2[])
        guess = Data.guess_vector_partner(plot_data.dataset, layer.variable[])
        layer.variable2[] = guess === nothing ?
            Constants.NOT_SELECTED_LABEL : guess
    end
    layer.plot_type[] = plot_type
    rebuild_layers!(fd)
    layer_status(fd, i)
end

"Take layer `i` off the figure."
function remove_layer!(fd::FigureData, i::Int)::String
    if i < 2
        @warn "The base field cannot be removed"
        return ""
    end
    if i > layer_count(fd)
        @warn "Layer $(layer_prefix(i)) is not set"
        return ""
    end
    name = layer_prefix(i)
    drop_layers!(fd, [i])
    rebuild_layers!(fd)
    "Removed layer $name."
end

# ============================================================
#  Animated-axis label rendering (title row / overlay)
# ============================================================

"Recompile the segments and rebuild both render targets."
function update_animlabel!(fd::FigureData)::Nothing
    ui_state = fd.ui.state
    fd.anim_config[] = resolve_anim_config(
        fd.plot_data.dataset, ui_state.pdim[], fd.settings)
    # share the resolved unit with the UI so the playback readout matches
    isequal(ui_state.anim_unit[], fd.anim_config[].unit) ||
        (ui_state.anim_unit[] = fd.anim_config[].unit)
    fd.anim_segments[] = compile_animlabel(
        fd.plot_data.dataset, ui_state.variable[], fd.plot_data.sel_dims[],
        ui_state.pdim[], fd.settings.animlabel[],
        fd.anim_config[], fd.settings.animlabelsize[])
    rebuild_header!(fd)
    rebuild_overlay!(fd)
    refresh_anim_values!(fd)
    nothing
end

"Per-frame: push the current value into each slot's text observable."
function refresh_anim_values!(fd::FigureData)::Nothing
    ui_state = fd.ui.state
    pdim = ui_state.pdim[]
    idx = get(ui_state.dim_obs[], pdim, nothing)
    idx === nothing && return nothing
    slot = 0
    for seg in fd.anim_segments[]
        seg.dynamic || continue
        slot += 1
        slot <= length(fd.anim_slots) || break
        rendered = render_slot(
            fd.plot_data.dataset, pdim, idx, seg.template, fd.anim_config[])
        # never write an empty string (degenerate text extent, see above)
        fd.anim_slots[slot][] = isempty(rendered) ? " " : rendered
    end
    nothing
end

"Grow the persistent slot-observable pool to at least `n` entries."
function ensure_slots!(fd::FigureData, n::Int)::Nothing
    while length(fd.anim_slots) < n
        # a slot is never empty: an empty-string Label has a degenerate
        # text extent whose NaN size poisons the whole figure solve
        push!(fd.anim_slots, Observable(" "))
    end
    nothing
end

"Delete the scene-anchored header plots (title + label segments)."
function clear_header!(fd::FigureData)::Nothing
    for (scene, plt) in fd.anim_header[]
        try
            delete!(scene, plt)
        catch
        end
    end
    fd.anim_header[] = Any[]
    nothing
end

"""
    fit_title_size(available, text, size)

The size the title is actually drawn at: the configured one, shrunk just
enough to leave the animated-axis label its share of the header line, and
never past `TITLESIZE_MIN`. The two share one line, so without this a
title long enough to reach across the plot box is simply drawn over the
label -- which a vector plot, naming both its components, easily is. Text
width is linear in the font size, so one division lands it. Measured in
the bold face the title is actually drawn in: the regular one is narrow
enough here to under-shrink by a good 15%.
"""
function fit_title_size(available::Real, text::AbstractString,
                        size::Real)::Float64
    width = measure_text(String(text), size, title_font())
    (width <= available || width <= 0) && return Float64(size)
    max(Float64(size) * Float64(available) / width,
        Float64(Constants.TITLESIZE_MIN))
end

"Width the animated-axis label claims of the header line, gap included."
function header_label_width(fd::FigureData)::Float64
    fd.settings.animlabelpos[] === :title || return 0.0
    segments = fd.anim_segments[]
    isempty(segments) && return 0.0
    sum(seg.width for seg in segments) + Float64(Constants.HEADER_GAP)
end

"""
    rebuild_header!(fd)

Draw the header -- the title on the left, the animated-axis label on the
right -- anchored to the top edge of the axis' plot box instead of laid
out at the figure top: an aspect-letterboxed axis floats centred in its
cell, and a layout header would leave a band of whitespace between the
title and the plot. Everything is positioned from the axis viewport, so
the header follows the plot wherever the layout puts it.
"""
function rebuild_header!(fd::FigureData)::Nothing
    clear_header!(fd)
    ax = fd.ax[]
    ax === nothing && return nothing
    scene = fd.fig.scene
    vp = ax.scene.viewport
    gap = Float64(Constants.HEADER_GAP)
    titlepos = @lift(Point2f($vp.origin[1],
                             $vp.origin[2] + $vp.widths[2] + gap))
    # the drawn size, not the configured one: it gives way to the label
    # rather than being drawn across it. Only ever shrinks, so the header
    # band (sized from the configured size) never has to grow for it.
    claimed = header_label_width(fd)
    titlesize = @lift(fit_title_size($vp.widths[1] - claimed, $(fd.title_text),
                                     $(fd.settings.titlesize)))
    plt = text!(scene, titlepos; text = fd.title_text,
                align = (:left, :bottom), font = :bold,
                fontsize = titlesize, space = :pixel,
                inspectable = false)
    push!(fd.anim_header[], (scene, plt))
    fd.settings.animlabelpos[] === :title || return nothing
    segments = fd.anim_segments[]
    isempty(segments) && return nothing
    fontsize = fd.settings.animlabelsize[]
    total = sum(seg.width for seg in segments)
    slot, xoff = 0, 0.0
    for seg in segments
        anchor = seg.dynamic ? xoff + seg.width : xoff
        pos = @lift(Point2f(
            $vp.origin[1] + $vp.widths[1] - total + anchor,
            $vp.origin[2] + $vp.widths[2] + gap))
        text_content = if seg.dynamic
            slot += 1
            ensure_slots!(fd, slot)
            fd.anim_slots[slot]
        else
            seg.text
        end
        plt = text!(scene, pos; text = text_content, space = :pixel,
                    align = (seg.dynamic ? :right : :left, :bottom),
                    fontsize = fontsize, inspectable = false)
        push!(fd.anim_header[], (scene, plt))
        xoff += seg.width
    end
    nothing
end

"Overlay geometry: the background rect for a corner, in scene pixels."
function animlabel_overlay_rect(
    viewport_widths, corner::Symbol, boxw::Float64, boxh::Float64,
)::Rect2f
    W, H = Float64(viewport_widths[1]), Float64(viewport_widths[2])
    inset = Float64(Constants.ANIMLABEL_PADDING)
    x = corner in (:lt, :lb) ? inset : W - inset - boxw
    y = corner in (:lb, :rb) ? inset : H - inset - boxh
    Rect2f(x, y, boxw, boxh)
end

"Delete the overlay plots of the previous configuration."
function clear_overlay!(fd::FigureData)::Nothing
    for (scene, plt) in fd.anim_overlay[]
        try
            delete!(scene, plt)
        catch
        end
    end
    fd.anim_overlay[] = Any[]
    nothing
end

"""
    rebuild_overlay!(fd)

Rebuild the in-plot overlay: the background box first, then one text per
segment, all in scene-pixel space so the geometry is exact. Slot texts are
right-aligned at their slot's trailing edge, so the static text around
them cannot move as the value changes length.
"""
function rebuild_overlay!(fd::FigureData)::Nothing
    clear_overlay!(fd)
    fd.settings.animlabelpos[] === :overlay || return nothing
    ax = fd.ax[]
    ax === nothing && return nothing
    segments = fd.anim_segments[]
    isempty(segments) && return nothing
    scene = ax.scene
    bpad = Float64(Constants.ANIMLABEL_BACKGROUND_PADDING)
    fontsize = fd.settings.animlabelsize[]
    boxw = sum(seg.width for seg in segments) + 2bpad
    boxh = maximum(measure_height(seg.text, fontsize)
                   for seg in segments) + 2bpad
    corner = fd.settings.animlabelcorner[]
    bg = fd.settings.animlabelbg[]
    rect = @lift(animlabel_overlay_rect(
        $(scene.viewport).widths, corner, boxw, boxh))
    box = poly!(scene, rect; space = :pixel,
                color = animlabel_background_color(bg),
                strokecolor = (:black, 0.8),
                strokewidth = animlabel_background_stroke(bg),
                inspectable = false)
    push!(fd.anim_overlay[], (scene, box))
    slot, xoff = 0, 0.0
    for seg in segments
        # the anchor: a slot anchors at its trailing edge (right-aligned),
        # static text at its leading edge
        anchor = seg.dynamic ? xoff + seg.width : xoff
        pos = @lift(begin
            r = animlabel_overlay_rect(
                $(scene.viewport).widths, corner, boxw, boxh)
            Point2f(r.origin[1] + bpad + anchor, r.origin[2] + bpad)
        end)
        text_content = if seg.dynamic
            slot += 1
            ensure_slots!(fd, slot)
            fd.anim_slots[slot]
        else
            seg.text
        end
        plt = text!(scene, pos; text = text_content, space = :pixel,
                    align = (seg.dynamic ? :right : :left, :bottom),
                    fontsize = fontsize, inspectable = false)
        push!(fd.anim_overlay[], (scene, plt))
        xoff += seg.width
    end
    nothing
end

function create_figure(figsize::Tuple{Int, Int})::Figure
    GLMakie.activate!()
    # create a theme
    cust_theme = Theme(
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
    theme = merge(theme_latexfonts(), theme_minimal())
    theme = merge(theme, cust_theme)
    # the theme must be active BEFORE the Figure is constructed: a figure
    # snapshots the global theme at creation, so setting it afterwards
    # left the first figure of a session in the default (sans) fonts
    set_theme!(theme)

    Figure(size = figsize)
end

function create_axis!(fig_data::FigureData, ui_state::UI.State)::Nothing
    if fig_data.ax[] !== nothing
        delete!(fig_data.ax[])
        # the layers went with it, so nothing is left to take off the axis
        for layer in fig_data.layers
            layer.plot_obj[] = nothing
        end
    end
    fig_data.ax[] = fig_data.plot_data.plot_type[].make_axis(fig_data)
    if !isnothing(fig_data.ax[])
        apply_kwargs!(fig_data, ui_state.kwargs[])
        if fig_data.data_inspector[] === nothing
            fig_data.data_inspector[] = DataInspector(fig_data.ax[])
        end
    end
    nothing
end

function add_earth!(fd::FigureData)::Nothing
    if fd.settings.earth[] && support_geographic(fd)
        # earth should be below the data
        if fd.ax[] isa GeoAxis
            fd.earth[] = surface!(fd.ax[],
                -180..180, -90..90,
                zeros(axes(rotr90(GeoMakie.earth())));
                shading = NoShading, color = rotr90(GeoMakie.earth()),
                transformation = (; translation = (0, 0, -10)),
                inspectable = false,
            )
        elseif fd.ax[] isa Axis
            fd.earth[] = image!(
                fd.ax[], -180..180, -90..90, GeoMakie.earth() |> rotr90;
                interpolate = false, transformation = (; translation = (0, 0, -10)),
                inspectable = false,
            )
        end
    end
    nothing
end

function add_land!(fd::FigureData)::Nothing
    if fd.settings.land[] && support_geographic(fd)
        land = GeoMakie.land()
        # land mask should be above the data but below coastlines
        fd.land[] = poly!(
            fd.ax[], land, color = :lightgray,
            transformation = (; translation = (0, 0, 40)),
            inspectable = false,
        )
    end
    nothing
end

function add_coastlines!(fd::FigureData)::Nothing
    if fd.settings.coastlines[] && support_geographic(fd)
        c = GeoMakie.coastlines(fd.settings.scale[])
        fd.coastlines[] = lines!(
            fd.ax[], c, color = :black,
            transformation = (; translation = (0, 0, 50)),
        )
    end
    nothing
end

function add_colorbar!(fd::FigureData)::Nothing
    if fd.cbar[] !== nothing
        delete!(fd.cbar[])
        fd.cbar[] = nothing
    end
    # one bar per figure, and it is the base layer's: an overlay carries
    # its own colors, but a second bar would need a second layout column
    if fd.plot_data.plot_type[].colorbar && primary(fd) !== nothing && fd.settings.cbar[]
        # A 2D axis with a constrained aspect letterboxes: it shrinks
        # inside its layout cell, while a cell-filling colorbar keeps the
        # full height and overshoots the plot. Tying the colorbar height
        # to the axis' actual on-screen height keeps the two flush; when
        # the axis fills its cell this equals the cell height, so the
        # unconstrained look is unchanged. Axis3 has no letterboxed plot
        # rectangle to match, so it keeps the plain cell-filling bar.
        ax = fd.ax[]
        size_kw = ax isa Axis3 ? (;) :
            (; height = @lift(Fixed($(ax.scene.viewport).widths[2])))
        # the label settings go in as observables, so changing one takes
        # effect on the spot; an empty label costs no space at all, which
        # keeps the unlabelled bar exactly as it was
        fd.cbar[] = Colorbar(fd.fig[2, 2], primary(fd);
            width = 30, tellwidth = false, tellheight = false,
            label = fd.cbar_label.text,
            labelrotation = fd.cbar_label.rotation,
            labelfont = fd.cbar_label.font,
            labelsize = fd.settings.cbarlabelsize,
            labelcolor = fd.settings.cbarlabelcolor,
            labelpadding = fd.settings.cbarlabelpadding,
            size_kw...)
        colsize!(fd.fig.layout, 2, Relative(0.05))
    end
    nothing
end

function clear_axis!(fd::FigureData)::Nothing
    if fd.cbar[] !== nothing
        delete!(fd.cbar[])
        fd.cbar[] = nothing
    end
    if fd.ax[] !== nothing
        delete!(fd.ax[])
        fd.ax[] = nothing
    end
    # the plots went with the axis; only the bookkeeping is left
    for layer in fd.layers
        layer.plot_obj[] = nothing
    end
    fd.earth[] = nothing
    fd.land[] = nothing
    fd.coastlines[] = nothing
    nothing
end

# ============================================================
#  Apply figure settings
# ============================================================
function enable_movable(ax::Makie.AbstractAxis)::Nothing
    activate_interaction!(ax, :dragpan)
    nothing
end

function disable_movable(ax::Makie.AbstractAxis)::Nothing
    deactivate_interaction!(ax, :dragpan)
    nothing
end

function set_movable!(fd::FigureData, moveable::Union{Bool, Nothing})::Bool
    ax = fd.ax[]
    isnothing(ax) && return false
    isnothing(moveable) && return false
    moveable ? enable_movable(ax) : disable_movable(ax)
    fd.settings.moveable[] = moveable
    false
end

function redraw!(fd::FigureData)::Nothing
    if !isnothing(fd.ax[])
        clear_axis!(fd)
        create_axis!(fd, fd.ui.state)
    end
    nothing
end

function set_geographic!(fd::FigureData, geographic::Bool)::Bool
    fd.settings.geographic[] = geographic
    true
end

function set_projection!(fd::FigureData, proj::Union{AbstractString, Nothing})::Bool
    fd.settings.proj[] = proj
    set_geographic!(fd, !isnothing(proj))
end

function resize_figure!(fd::FigureData, new_size::Tuple{Int, Int})::Bool
    try
        resize!(fd.fig, new_size[1], new_size[2])
        fd.settings.figsize[] = new_size
    catch e
        @error "Error resizing figure: $e"
    end
    false
end

function set_colorbar!(fd::FigureData, show::Bool)::Bool
    if show && !fd.plot_data.plot_type[].colorbar
        @warn "Current plot type does not support colorbar"
    end
    fd.settings.cbar[] = show
    add_colorbar!(fd)
    false
end

function set_earth!(fd::FigureData, show::Bool)::Bool
    fd.settings.earth[] = show
    true
end

function set_land!(fd::FigureData, show::Bool)::Bool
    fd.settings.land[] = show
    true
end

function set_coastlines!(fd::FigureData, show::Bool)::Bool
    fd.settings.coastlines[] = show
    true
end

function set_scale!(fd::FigureData, scale::Int)::Bool
    avail = Constants.GEOGRAPHIC_DATA_SCALES
    if scale ∉ avail
        @warn "Scale $scale not available. Available scales are: $avail"
        return false
    end
    fd.settings.scale[] = scale
    true
end

struct FigureSettingsHandler
    property::Symbol
    type::Type
    handler::Function
end

"The background colour of the overlay label; fully transparent when off."
animlabel_background_color(bg) =
    bg === false ? (:white, 0.0) :
    bg === true ? Constants.ANIMLABEL_BACKGROUND_COLOR : bg

"The background outline width; no outline when the background is off."
animlabel_background_stroke(bg)::Int = bg === false ? 0 : 1

# ------------------------------------------------------------
#  Animated-axis label settings
#
#  All of these only feed observables the title/overlay lift from, so none
#  of them needs a redraw: updating the observable re-renders the label.
# ------------------------------------------------------------
function set_animlabel!(fd::FigureData, value::Union{Bool, AbstractString})::Bool
    fd.settings.animlabel[] = value isa AbstractString ? String(value) : value
    false
end

function set_animlabelpos!(fd::FigureData, value::Union{Symbol, AbstractString})::Bool
    pos = Symbol(value)
    if pos ∉ Constants.ANIMLABEL_POSITIONS
        @error "animlabelpos must be one of $(Constants.ANIMLABEL_POSITIONS), got :$(pos)"
        return false
    end
    fd.settings.animlabelpos[] = pos
    false
end

function set_animlabelcorner!(fd::FigureData, value::Union{Symbol, AbstractString})::Bool
    corner = Symbol(value)
    if corner ∉ Constants.ANIMLABEL_CORNERS
        @error "animlabelcorner must be one of $(Constants.ANIMLABEL_CORNERS), got :$(corner)"
        return false
    end
    fd.settings.animlabelcorner[] = corner
    false
end

function set_animlabelbg!(fd::FigureData, value::Any)::Bool
    fd.settings.animlabelbg[] = value
    false
end

function set_titlesize!(fd::FigureData, value::Real)::Bool
    fd.settings.titlesize[] = Float64(value)
    false
end

function set_animlabelsize!(fd::FigureData, value::Real)::Bool
    fd.settings.animlabelsize[] = Float64(value)
    false
end

function set_title!(fd::FigureData, value::Union{Nothing, AbstractString})::Bool
    fd.settings.title[] = value === nothing ? nothing : String(value)
    false
end

function set_animlabelnumfmt!(fd::FigureData, value::AbstractString)::Bool
    fd.settings.animlabelnumfmt[] = String(value)
    false
end

function set_animlabeldateformat!(fd::FigureData, value::AbstractString)::Bool
    fd.settings.animlabeldateformat[] = String(value)
    false
end

# ------------------------------------------------------------
#  Colorbar label settings
#
#  The colorbar reads these observables, so none of them needs a redraw.
#  A plot type without a colorbar stores the value silently and starts
#  showing it once a colorbar-bearing type is selected -- warning here
#  would trip the kwargs path's revert-on-stderr machinery.
# ------------------------------------------------------------
function set_cbarlabel!(fd::FigureData,
                        value::Union{Nothing, Bool, AbstractString})::Bool
    fd.settings.cbarlabel[] = value isa AbstractString ? String(value) : value
    false
end

function set_cbarlabelsize!(fd::FigureData, value::Real)::Bool
    fd.settings.cbarlabelsize[] = Float64(value)
    false
end

function set_cbarlabelcolor!(fd::FigureData, value::Any)::Bool
    fd.settings.cbarlabelcolor[] = value
    false
end

function set_cbarlabelfont!(fd::FigureData, value::AbstractString)::Bool
    fd.settings.cbarlabelfont[] = String(value)
    false
end

"Rotate the label; nothing keeps Makie's automatic orientation."
function set_cbarlabelrotation!(fd::FigureData, value::Union{Nothing, Real})::Bool
    fd.settings.cbarlabelrotation[] = value === nothing ? nothing : Float64(value)
    false
end

function set_cbarlabelpadding!(fd::FigureData, value::Real)::Bool
    fd.settings.cbarlabelpadding[] = Float64(value)
    false
end

# ------------------------------------------------------------
#  Axis display units
#
#  Changing a unit returns true (redraw): the axis is recreated with the
#  converted ticks and label, and the user's kwargs reapply on top.
# ------------------------------------------------------------
function set_axis_unit!(fd::FigureData, which::Symbol, unit_obs::Observable,
                        name_obs::Observable,
                        value::Union{Nothing, AbstractString})::Bool
    unit = value === nothing ? nothing : String(value)
    if unit !== nothing
        if RescaleUnits.display_unit(unit) === nothing
            supported = join(RescaleUnits.display_unit_names(), ", ")
            @error "$which must be one of ($supported), got \"$unit\""
            return false
        end
        if axis_unit_factor(fd, name_obs[], unit) === nothing
            native = RescaleUnits.get_unit(fd.plot_data.dataset.ds, name_obs[])
            native_str = native == "" ? "no unit" : "unit \"$native\""
            @warn ("The $(name_obs[]) axis ($native_str) cannot be " *
                   "displayed in \"$unit\"; keeping native ticks")
        end
    end
    unit_obs[] = unit
    true
end

"""
Set the display unit of the animated-axis label. Unknown spellings are
rejected; a unit the current playback dimension cannot convert into is
stored anyway (it applies once a compatible dimension is selected) but
warned about, and the label keeps native values meanwhile. No redraw:
the label rebuilds reactively.
"""
function set_animunit!(fd::FigureData, value::Union{Nothing, AbstractString})::Bool
    unit = value === nothing ? nothing : String(value)
    if unit !== nothing && unit != "auto"
        if RescaleUnits.display_unit(unit) === nothing
            supported = join(RescaleUnits.display_unit_names(), ", ")
            @error "animunit must be \"auto\" or one of ($supported), got \"$unit\""
            return false
        end
        pdim = fd.ui.state.pdim[]
        if pdim != Constants.NOT_SELECTED_LABEL &&
           Data.dim_unit_factor(fd.plot_data.dataset, pdim, unit) === nothing
            native = RescaleUnits.get_unit(fd.plot_data.dataset.ds, pdim)
            native_str = native == "" ? "no unit" : "unit \"$native\""
            @warn ("The playback dimension $pdim ($native_str) cannot be " *
                   "displayed in \"$unit\"; keeping native values")
        end
    end
    fd.settings.animunit[] = unit
    false
end

# Camera rotation speeds; stored even without a 3D axis (a warning here
# would trip the kwargs path's revert-on-stderr machinery), so the value
# simply starts applying once an Axis3 plot type is active. A negative
# speed seeds the initial direction of a bounded (bouncing) motion.
function set_rotate!(fd::FigureData, value::Real)::Bool
    fd.settings.rotate[] = Float64(value)
    fd.camera_hdir[] = value < 0 ? -1.0 : 1.0
    false
end
function set_rotatev!(fd::FigureData, value::Real)::Bool
    fd.settings.rotatev[] = Float64(value)
    fd.camera_vdir[] = value < 0 ? -1.0 : 1.0
    false
end

"Set the azimuth sector for horizontal rotation; nothing = full orbit."
function set_rotatelim!(fd::FigureData, value::Union{Nothing, Tuple})::Bool
    if value !== nothing
        ok = length(value) == 2 && all(x -> x isa Real && isfinite(x), value) &&
             value[1] < value[2]
        if !ok
            @error ("rotatelim must be an increasing (lo, hi) azimuth " *
                    "tuple in degrees, got $value")
            return false
        end
    end
    fd.settings.rotatelim[] = value === nothing ? nothing :
        (Float64(value[1]), Float64(value[2]))
    false
end

"Set the elevation range the vertical rotation bounces in (degrees)."
function set_rotatevlim!(fd::FigureData, value::Tuple)::Bool
    ok = length(value) == 2 && all(x -> x isa Real && isfinite(x), value)
    # at exactly ±90° the azimuth becomes degenerate, so stay inside
    lo = ok ? clamp(Float64(value[1]), -89.0, 89.0) : 0.0
    hi = ok ? clamp(Float64(value[2]), -89.0, 89.0) : 0.0
    if !ok || lo >= hi
        @error ("rotatevlim must be an increasing (lo, hi) elevation " *
                "tuple within ±89 degrees, got $value")
        return false
    end
    fd.settings.rotatevlim[] = (lo, hi)
    false
end

# ------------------------------------------------------------
#  Vector plot density
#
#  `arrows` targets a number of arrows per axis, `every` picks exact grid
#  points and overrides the target. Both are read while the arrows are
#  laid out, so re-notifying the data observable is enough -- no redraw,
#  which would throw the user's zoom away. A plot type without arrows
#  stores the value silently and starts using it once a vector type is
#  selected; warning here would trip the kwargs path's revert-on-stderr
#  machinery (see set_rotate!).
# ------------------------------------------------------------

# only the arrows sample the grid; streamlines follow the field, so the
# density settings mean nothing to them and re-laying one would just
# integrate every streamline again for no visible change
is_arrow_type(fd::FigureData, i::Int = 1)::Bool =
    layer_plot(fd, i).type == "quiver"

"How many arrows layer `i` aims for: its own setting, else the figure's."
function layer_arrows(fd::FigureData, i::Int)::Tuple{Int, Int}
    i <= length(fd.layers) || return fd.settings.arrows[]
    own = fd.layers[i].settings.arrows
    own === nothing ? fd.settings.arrows[] : own
end

"The exact grid stride layer `i` samples at, or nothing (a target count)."
function layer_every(fd::FigureData, i::Int)::Union{Nothing, Int}
    i <= length(fd.layers) || return fd.settings.every[]
    own = fd.layers[i].settings.every
    own === nothing ? fd.settings.every[] : own
end

"Re-lay the arrows of every vector layer, without rebuilding them."
function refresh_vector_density!(fd::FigureData)::Nothing
    plot_data = fd.plot_data
    for i in eachindex(plot_data.layers)
        is_arrow_type(fd, i) || continue
        ndims = layer_plot(fd, i).ndims
        ndims in eachindex(plot_data.d[i][1]) || continue
        notify(plot_data.d[i][1][ndims])
    end
    nothing
end

function set_arrows!(fd::FigureData, value::Tuple)::Bool
    ok = length(value) == 2 && all(v -> v isa Integer && v > 0, value)
    if !ok
        @error ("arrows must be an (nx, ny) tuple of positive integers, " *
                "got $value")
        return false
    end
    fd.settings.arrows[] = (Int(value[1]), Int(value[2]))
    refresh_vector_density!(fd)
    false
end

function set_every!(fd::FigureData, value::Union{Nothing, Integer})::Bool
    if value !== nothing && value < 1
        @error "every must be a positive integer, got $value"
        return false
    end
    fd.settings.every[] = value === nothing ? nothing : Int(value)
    refresh_vector_density!(fd)
    false
end

set_xunit!(fd::FigureData, value::Union{Nothing, AbstractString})::Bool =
    set_axis_unit!(fd, :xunit, fd.settings.xunit, fd.ui.state.x_name, value)
set_yunit!(fd::FigureData, value::Union{Nothing, AbstractString})::Bool =
    set_axis_unit!(fd, :yunit, fd.settings.yunit, fd.ui.state.y_name, value)
set_zunit!(fd::FigureData, value::Union{Nothing, AbstractString})::Bool =
    set_axis_unit!(fd, :zunit, fd.settings.zunit, fd.ui.state.z_name, value)

const FIGURE_SETTINGS_HANDLERS = Dict{Symbol, FigureSettingsHandler}(
    :figsize => FigureSettingsHandler(:figsize, Tuple{Int, Int}, resize_figure!),
    :cbar => FigureSettingsHandler(:cbar, Bool, set_colorbar!),
    :moveable => FigureSettingsHandler(:moveable, Union{Bool, Nothing}, set_movable!),
    :geographic => FigureSettingsHandler(:geographic, Bool, set_geographic!),
    :proj => FigureSettingsHandler(:proj, Union{AbstractString, Nothing}, set_projection!),
    :scale => FigureSettingsHandler(:scale, Int, set_scale!),
    :earth => FigureSettingsHandler(:earth, Bool, set_earth!),
    :land => FigureSettingsHandler(:land, Bool, set_land!),
    :coastlines => FigureSettingsHandler(:coastlines, Bool, set_coastlines!),
    :animlabel => FigureSettingsHandler(
        :animlabel, Union{Bool, AbstractString}, set_animlabel!),
    :animlabelpos => FigureSettingsHandler(
        :animlabelpos, Union{Symbol, AbstractString}, set_animlabelpos!),
    :animlabelcorner => FigureSettingsHandler(
        :animlabelcorner, Union{Symbol, AbstractString}, set_animlabelcorner!),
    :animlabelnumfmt => FigureSettingsHandler(
        :animlabelnumfmt, AbstractString, set_animlabelnumfmt!),
    :animlabeldateformat => FigureSettingsHandler(
        :animlabeldateformat, AbstractString, set_animlabeldateformat!),
    :animlabelbg => FigureSettingsHandler(:animlabelbg, Any, set_animlabelbg!),
    :animunit => FigureSettingsHandler(
        :animunit, Union{Nothing, AbstractString}, set_animunit!),
    :title => FigureSettingsHandler(
        :title, Union{Nothing, AbstractString}, set_title!),
    :titlesize => FigureSettingsHandler(:titlesize, Real, set_titlesize!),
    :animlabelsize => FigureSettingsHandler(
        :animlabelsize, Real, set_animlabelsize!),
    :cbarlabel => FigureSettingsHandler(
        :cbarlabel, Union{Nothing, Bool, AbstractString}, set_cbarlabel!),
    :cbarlabelsize => FigureSettingsHandler(
        :cbarlabelsize, Real, set_cbarlabelsize!),
    :cbarlabelcolor => FigureSettingsHandler(
        :cbarlabelcolor, Any, set_cbarlabelcolor!),
    :cbarlabelfont => FigureSettingsHandler(
        :cbarlabelfont, AbstractString, set_cbarlabelfont!),
    :cbarlabelrotation => FigureSettingsHandler(
        :cbarlabelrotation, Union{Nothing, Real}, set_cbarlabelrotation!),
    :cbarlabelpadding => FigureSettingsHandler(
        :cbarlabelpadding, Real, set_cbarlabelpadding!),
    :xunit => FigureSettingsHandler(
        :xunit, Union{Nothing, AbstractString}, set_xunit!),
    :yunit => FigureSettingsHandler(
        :yunit, Union{Nothing, AbstractString}, set_yunit!),
    :zunit => FigureSettingsHandler(
        :zunit, Union{Nothing, AbstractString}, set_zunit!),
    :rotate => FigureSettingsHandler(:rotate, Real, set_rotate!),
    :rotatev => FigureSettingsHandler(:rotatev, Real, set_rotatev!),
    :rotatelim => FigureSettingsHandler(
        :rotatelim, Union{Nothing, Tuple}, set_rotatelim!),
    :rotatevlim => FigureSettingsHandler(:rotatevlim, Tuple, set_rotatevlim!),
    :arrows => FigureSettingsHandler(:arrows, Tuple, set_arrows!),
    :every => FigureSettingsHandler(
        :every, Union{Nothing, Integer}, set_every!),
)
    

function apply_figure_settings!(fd::FigureData, property::Symbol, value::Any)::Bool
    redraw = false
    if haskey(FIGURE_SETTINGS_HANDLERS, property)
        handler = FIGURE_SETTINGS_HANDLERS[property]
        if isa(value, handler.type)
            res = handler.handler(fd, value)
            redraw = res ? true : redraw
        else
            @error "Value for $property must be of type $(handler.type), got $(typeof(value))"
        end
    else
        @error "Property $property not recognized in FigureData"
    end
    redraw
end

# ============================================================
#  Pinned color range: reconciliation
# ============================================================

"""
    layer_kwarg(fd, i, key)

One layer's value of a keyword: the prefixed form (`over.levels`) when it
is set, and the unprefixed one otherwise. With a single layer this is
exactly `kwargs[key]`.
"""
function layer_kwarg(fd::FigureData, i::Int, key::Symbol)::Any
    kwargs = fd.ui.state.kwargs[]
    prefixed = Symbol(layer_prefix(i), '.', key)
    haskey(kwargs, prefixed) && return kwargs[prefixed]
    get(kwargs, key, nothing)
end

"Whether either form of a keyword is set for layer `i`."
function layer_kwarg_set(fd::FigureData, i::Int, key::Symbol)::Bool
    kwargs = fd.ui.state.kwargs[]
    haskey(kwargs, Symbol(layer_prefix(i), '.', key)) || haskey(kwargs, key)
end

"The colorrange mode of layer `i`: :manual, or a mode symbol."
function colorrange_mode(fd::FigureData, i::Int = 1)::Symbol
    value = layer_kwarg(fd, i, :colorrange)
    value === nothing && return :cycle
    if value isa AbstractString || value isa Symbol
        s = String(value)
        s in CRANGE_MODES && return Symbol(s)
        return :cycle  # invalid mode strings were rejected with an error
    end
    :manual
end

"Whether the user chose the mode (an explicit choice bypasses the gate)."
colorrange_explicit(fd::FigureData, i::Int = 1)::Bool =
    layer_kwarg_set(fd, i, :colorrange)

"The playback dimension when it is actually animatable, else nothing."
function scan_pdim(fd::FigureData, variable::String)::Union{Nothing, String}
    pdim = fd.ui.state.pdim[]
    pdim == Constants.NOT_SELECTED_LABEL && return nothing
    pdim ∈ fd.plot_data.sel_dims[] && return nothing
    pdim ∈ Data.get_var_dims(fd.plot_data.dataset, variable) || return nothing
    pdim
end

"The hyperslab key the active mode wants pinned, or nothing (autoscale)."
function colorrange_key(fd::FigureData, mode::Symbol, i::Int = 1)::Any
    variables = layer_variables(fd, i)
    variable = variables[1]
    dataset = fd.plot_data.dataset
    haskey(dataset.var_coords, variable) || return nothing
    keep = if mode === :data
        copy(dataset.var_coords[variable])
    else
        pdim = scan_pdim(fd, variable)
        # without an animatable dimension there is nothing to stabilize
        pdim === nothing && return nothing
        vcat(fd.plot_data.sel_dims[], [pdim])
    end
    indexing = try
        DataLimits.scan_indexing(dataset, variable, keep,
                                 fd.plot_data.dim_obs[])
    catch
        return nothing
    end
    (Tuple(variables), Tuple(indexing))
end

# contour plots re-bin an Int `levels` from each frame's extrema, so the
# pin must hand them concrete boundaries; a colorrange alone won't hold
is_contour_type(fd::FigureData, i::Int = 1)::Bool =
    layer_plot(fd, i).type in ("contour", "contourf", "contour3d")

"""
    user_levels(fd, i)

The `levels` keyword layer `i` is drawn with (an explicit vector always
wins over the pin). Per layer, not per figure: two contour layers each
count their own lines.
"""
user_levels(fd::FigureData, i::Int = 1)::Any = layer_kwarg(fd, i, :levels)

function pin_levels!(fd::FigureData, i::Int, lo::Float64, hi::Float64)::Nothing
    is_contour_type(fd, i) || return nothing
    levels = user_levels(fd, i)
    levels isa AbstractVector && return nothing
    plot = fd.layers[i].plot_obj[]
    (plot === nothing || :levels ∉ propertynames(plot)) && return nothing
    scan = fd.layers[i].crange_scan
    if scan.base_levels === nothing
        current = plot.levels[]
        current isa Int || return nothing  # someone else owns the levels
        scan.base_levels = current
    end
    count = levels isa Int ? levels : scan.base_levels
    # an Int means band boundaries for contourf, line values for contour
    edges = layer_plot(fd, i).type == "contourf" ? count + 1 : count
    # a range, not a vector: Makie's compute graph types the levels edge
    # from its first render, and Base converts between range types where
    # a vector would not convert into a frozen range-typed edge
    plot.levels[] = range(lo, hi; length = edges)
    nothing
end

"Hand a pinned Int `levels` back to the plot."
function restore_levels!(fd::FigureData, i::Int)::Nothing
    scan = fd.layers[i].crange_scan
    scan.base_levels === nothing && return nothing
    plot = fd.layers[i].plot_obj[]
    if plot !== nothing && :levels ∈ propertynames(plot)
        levels = user_levels(fd, i)
        plot.levels[] = levels isa Int ? levels : scan.base_levels
    end
    scan.base_levels = nothing
    nothing
end

"Apply a computed range to the plot, remembering what is pinned."
function apply_colorrange_pin!(fd::FigureData, key::Any,
                               range::NTuple{2, Float64}, i::Int = 1)::Nothing
    plot = fd.layers[i].plot_obj[]
    plot === nothing && return nothing
    lo, hi = range
    lo == hi && ((lo, hi) = (lo - 0.5, hi + 0.5))  # degenerate data
    fd.layers[i].crange_scan.applied_key = key
    :colorrange ∈ propertynames(plot) && (plot.colorrange[] = (lo, hi))
    pin_levels!(fd, i, lo, hi)
    nothing
end

"Return the plot to Makie's own autoscaling and its own levels."
function unpin_colorrange!(fd::FigureData, i::Int)::Nothing
    fd.layers[i].crange_scan.applied_key = nothing
    plot = fd.layers[i].plot_obj[]
    plot === nothing && return nothing
    :colorrange ∈ propertynames(plot) && (plot.colorrange[] = Makie.automatic)
    restore_levels!(fd, i)
    nothing
end

"""
    gate_colorrange_keys!(fd, targets)

Blank the keys whose scans the automatic budget will not pay for, and say
so once. The budget is figure-wide on purpose: the scans do not run in
parallel (`@async` here is cooperative on the one thread the UI lives on),
so a second layer doubles both the wall time and the time the interface is
blocked. Gating each scan on its own would let exactly that through
unnoticed.
"""
function gate_colorrange_keys!(fd::FigureData,
                               targets::Vector{Tuple{Symbol, Any}},
                               )::Vector{Tuple{Symbol, Any}}
    total = 0
    gated = Int[]
    for (i, (_, key)) in enumerate(targets)
        key === nothing && continue
        haskey(fd.layers[i].crange_scan.cache, key) && continue
        # an explicit choice bypasses the gate: the user asked for it
        colorrange_explicit(fd, i) && continue
        total += DataLimits.hyperslab_elements(
            fd.plot_data.dataset, collect(String, key[1]),
            collect(Union{Colon, Int}, key[2]))
        push!(gated, i)
    end
    (isempty(gated) || total <= DataLimits.AUTO_SCAN_ELEMENTS[]) && return targets
    if !fd.crange_hinted[]
        fd.crange_hinted[] = true
        @info ("Automatic color-range pinning skipped: this view " *
               "spans $total values. Set colorrange=\"cycle\" " *
               "to scan anyway, or pin a manual colorrange=(lo, hi).")
    end
    [i ∈ gated ? (mode, nothing) : (mode, key)
     for (i, (mode, key)) in enumerate(targets)]
end

"""
    update_colorrange!(fd; sync = false)

Reconcile every layer's color range with the mode it is under. Cheap when
nothing changed (the per-frame path during playback): the target keys are
recomputed and compared before any work happens. A cache miss starts a
background scan -- or runs it inline with `sync = true`, which record
uses so a video never rescales mid-file. The previous pin stays applied
until its replacement is ready.
"""
function update_colorrange!(fd::FigureData; sync::Bool = false)::Nothing
    targets = Tuple{Symbol, Any}[]
    for i in eachindex(fd.layers)
        # nothing drawn yet: skip before the key is even derived, so the
        # per-frame path stays as cheap as it was
        if fd.layers[i].plot_obj[] === nothing
            push!(targets, (:frame, nothing))
            continue
        end
        mode = colorrange_mode(fd, i)
        key = mode === :manual || mode === :frame ? nothing :
            colorrange_key(fd, mode, i)
        push!(targets, (mode, key))
    end
    # the size gate spends one budget across all of them
    targets = gate_colorrange_keys!(fd, targets)
    for (i, (mode, key)) in enumerate(targets)
        update_layer_colorrange!(fd, i, mode, key; sync = sync)
    end
    nothing
end

"Reconcile one layer, given the mode and the key the gate left it with."
function update_layer_colorrange!(fd::FigureData, i::Int, mode::Symbol,
                                  key::Any; sync::Bool = false)::Nothing
    plot = fd.layers[i].plot_obj[]
    plot === nothing && return nothing
    scan = fd.layers[i].crange_scan
    if mode === :manual
        value = layer_kwarg(fd, i, :colorrange)
        manual_key = (:manual, value)
        manual_key == scan.applied_key && return nothing
        scan.generation += 1
        scan.pending_key = nothing
        restore_levels!(fd, i)
        # write the range, do not just record it: the kwargs path set it
        # already, but apply_kwargs! yields while it waits for its render
        # cycles, and a scan started before the manual range can land in
        # that window and overwrite it. Reconciling last has to win.
        if value isa Tuple && length(value) == 2 && all(x -> x isa Real, value)
            :colorrange ∈ propertynames(plot) && (plot.colorrange[] = value)
            pin_levels!(fd, i, Float64(value[1]), Float64(value[2]))
        end
        scan.applied_key = manual_key
        return nothing
    end
    key !== nothing && key == scan.applied_key && return nothing
    if key === nothing
        scan.applied_key === nothing && return nothing
        scan.generation += 1
        scan.pending_key = nothing
        unpin_colorrange!(fd, i)
        return nothing
    end
    if haskey(scan.cache, key)
        scan.generation += 1
        scan.pending_key = nothing
        apply_colorrange_pin!(fd, key, scan.cache[key], i)
        return nothing
    end
    !sync && key == scan.pending_key && return nothing  # already scanning
    scan.generation += 1
    generation = scan.generation
    scan.pending_key = key
    dataset = fd.plot_data.dataset
    runner = () -> begin
        result = DataLimits.hyperslab_extrema(
            dataset, collect(String, key[1]),
            collect(Union{Colon, Int}, key[2]);
            abort = () -> scan.generation != generation)
        scan.generation == generation || return
        scan.pending_key = nothing
        result === nothing && return
        scan.cache[key] = result
        # a manual range applied while this scan ran owns the plot now:
        # keep the result cached, but never paint over the user's range
        colorrange_mode(fd, i) === :manual && return
        apply_colorrange_pin!(fd, key, result, i)
    end
    sync ? runner() : (scan.task = @async runner())
    nothing
end

# ============================================================
#  Camera rotation (Axis3)
# ============================================================

"""
    bounce_step(value, step, lo, hi, direction)

One step of a bouncing motion between `lo` and `hi`: `direction`
reverses at the bounds, and a value starting outside them (a dragged
camera, tightened limits) travels smoothly back toward the range
instead of snapping into it.
"""
function bounce_step(value::Float64, step::Float64, lo::Float64, hi::Float64,
                     direction::Base.RefValue{Float64})::Float64
    value > hi && (direction[] = -1.0)
    value < lo && (direction[] = 1.0)
    new = value + direction[] * step
    # bounce only when crossing a bound from inside
    if new > hi && value <= hi
        direction[] = -1.0
        new = hi
    elseif new < lo && value >= lo
        direction[] = 1.0
        new = lo
    end
    new
end

"""
    rotate_camera!(fd, dt)

Advance the Axis3 camera by `dt` seconds of the configured rotation.
Driven by the render tick; during recording Makie emits one tick per
frame with dt = 1/framerate, so videos rotate at exactly the set speed.
The elevation bounces inside `rotatevlim`; the azimuth orbits freely
unless `rotatelim` bounds it to a sector.
"""
function rotate_camera!(fd::FigureData, dt::Real)::Nothing
    horizontal = fd.settings.rotate[]
    vertical = fd.settings.rotatev[]
    horizontal == 0.0 && vertical == 0.0 && return nothing
    ax = fd.ax[]
    ax isa Axis3 || return nothing
    (isfinite(dt) && dt > 0) || return nothing
    dt = min(Float64(dt), 0.1)  # a lag spike must not jolt the camera
    if horizontal != 0.0
        hlim = fd.settings.rotatelim[]
        if hlim === nothing
            ax.azimuth[] += deg2rad(horizontal) * dt
        else
            ax.azimuth[] = bounce_step(
                Float64(ax.azimuth[]), deg2rad(abs(horizontal)) * dt,
                deg2rad(hlim[1]), deg2rad(hlim[2]), fd.camera_hdir)
        end
    end
    if vertical != 0.0
        vlim = fd.settings.rotatevlim[]
        ax.elevation[] = bounce_step(
            Float64(ax.elevation[]), deg2rad(abs(vertical)) * dt,
            deg2rad(vlim[1]), deg2rad(vlim[2]), fd.camera_vdir)
    end
    nothing
end

# ============================================================
#  Apply keyword arguments to plot objects
# ============================================================

"""
One keyword aimed at one target. `key` is the keyword exactly as the user
wrote it, layer prefix and all, and `property` the name it resolved to on
the target. The two differ for a prefixed keyword, and the store is keyed
by `key`: strip the prefix there and `over.colormap` and `colormap` would
collapse onto one entry and overwrite each other's remembered value.
"""
struct PropertyMapping
    key::Symbol
    property::Symbol
    target_object::Any
    current_value::Any
    intended_value::Any
end

function get_default_value(fd::FigureData, target_object::Any, property::Symbol)::Any
    # a layer setting falls back to the figure's own
    isa(target_object, LayerSettings) && return nothing
    if isa(target_object, Interpolate.RangeControl)
        interp = fd.ui.state.range_control[].interp
        try
            return Interpolate.get_default_range(interp, String(property))
        catch
            return :delete
        end
    elseif isa(target_object, FigureSettings)
        defaults = Dict(
            :figsize => Constants.FIGSIZE,
            :cbar => true,
            :moveable => true,
            :geographic => false,
            :proj => nothing,
            :scale => 110,
            :earth => false,
            :land => false,
            :coastlines => true,
            :animlabel => true,
            :animlabelpos => Constants.ANIMLABEL_POSITION,
            :animlabelnumfmt => Constants.ANIMLABEL_NUMFMT,
            :animlabeldateformat => Constants.DATETIME_FORMAT,
            :animlabelcorner => Constants.ANIMLABEL_CORNER,
            :animlabelbg => Constants.ANIMLABEL_BACKGROUND,
            :animunit => nothing,
            :title => nothing,
            :titlesize => Float64(Constants.TITLESIZE),
            :animlabelsize => Float64(Constants.LABELSIZE),
            :cbarlabel => nothing,
            :cbarlabelsize => Float64(Constants.LABELSIZE),
            :cbarlabelcolor => Constants.CBARLABEL_COLOR,
            :cbarlabelfont => Constants.CBARLABEL_FONT,
            :cbarlabelrotation => nothing,
            :cbarlabelpadding => Float64(Constants.CBARLABEL_PADDING),
            :xunit => nothing,
            :yunit => nothing,
            :zunit => nothing,
            :rotate => 0.0,
            :rotatev => 0.0,
            :rotatelim => nothing,
            :rotatevlim => (0.0, 80.0),
            :arrows => Constants.VECTOR_ARROWS,
            :every => nothing,
        )
        return haskey(defaults, property) ? defaults[property] : :delete
    elseif isa(target_object, Makie.AbstractAxis)
        unit_ticks = unit_ticks_kwargs(fd)
        defaults = Dict(
            :xlabel => fd.plot_data.labels.xlabel[],
            :ylabel => fd.plot_data.labels.ylabel[],
            :zlabel => fd.plot_data.labels.zlabel[],
            # deleting a user xticks override restores the unit ticks
            :xticks => get(unit_ticks, :xticks, Makie.automatic),
            :yticks => get(unit_ticks, :yticks, Makie.automatic),
            :zticks => get(unit_ticks, :zticks, Makie.automatic),
        )
        return haskey(defaults, property) ? defaults[property] : :delete
    end
    
    :delete
end
    

"""
    kwarg_targets(fig_data)

Everything a keyword can name, in the order `get` reports them: the axis,
then the layers base first, then the colorbar, the figure settings and the
coordinate ranges. A keyword reaches *every* target owning it, so
`colorrange=(-20, 30)` still pins both a heatmap and its colorbar.
"""
function kwarg_targets(fig_data::FigureData)::Vector{Any}
    targets = Any[fig_data.ax[]]
    for layer in fig_data.layers
        push!(targets, layer.plot_obj[])
    end
    push!(targets, fig_data.cbar[], fig_data.settings,
          fig_data.range_control[])
    targets
end

"""
    resolve_kwarg(fig_data, key)

Where a keyword goes: the property it names and every object owning it.

The whole key is tried first, against the flat namespace of every target
there is. Only when nothing owns it is it read as `over2.levels` -- a
layer prefix and a property -- and resolved against that one layer: its
own settings, and failing those its plot. That order is what keeps the
meaning of every keyword that worked before overlays existed, coordinate
names with a dot in them included.
"""
function resolve_kwarg(fig_data::FigureData,
                       key::Symbol)::Tuple{Symbol, Vector{Any}}
    owners(property, targets) = Any[
        t for t in targets
        if t !== nothing && property ∈ propertynames(t) &&
        # the figure title lives in a layout Label; never touch the axis'
        # native (empty) title
        !(property in (:title, :titlesize) && t isa Makie.AbstractAxis)]
    targets = owners(key, kwarg_targets(fig_data))
    isempty(targets) || return (key, targets)
    split = split_layer_key(key)
    split === nothing && return (key, targets)
    layer, property = split
    layer <= length(fig_data.layers) || return (key, Any[])
    # the layer's own settings win over an attribute of the same name on
    # its plot: `over.arrows` is the overlay's arrow count, full stop
    settings = owners(property, Any[fig_data.layers[layer].settings])
    isempty(settings) || return (property, settings)
    (property, owners(property, Any[fig_data.layers[layer].plot_obj[]]))
end

function get_property_mappings(kwargs::OrderedDict{Symbol, Any}, fig_data::FigureData)::Vector{PropertyMapping}
    mappings = Vector{PropertyMapping}()
    for (key, intended_value) in kwargs
        property, targets = resolve_kwarg(fig_data, key)
        # colorrange mode strings configure the range scanner; Makie only
        # ever sees tuples
        if property === :colorrange && intended_value !== :delete &&
           (intended_value isa AbstractString || intended_value isa Symbol)
            String(intended_value) in CRANGE_MODES ||
                @error ("colorrange must be a (lo, hi) tuple or one of " *
                        "(" * join(CRANGE_MODES, ", ") *
                        "), got \"$intended_value\"")
            continue
        end
        for target_obj in targets
            # Get the current value of the property
            current_value = getproperty(target_obj, property)
            # If it's an Observable, get its value
            current_value = try
                current_value[]
            catch
                current_value  # not an observable
            end

            # a deletion resolves per target: keep the loop variable
            # intact so the next target still sees the :delete request
            target_value = intended_value === :delete ?
                get_default_value(fig_data, target_obj, property) : intended_value

            push!(mappings, PropertyMapping(key, property, target_obj,
                                            current_value, target_value))
        end
        isempty(targets) && @warn "Property $key not found in any plot object"
    end
    return mappings
end

function set_property_mapping(fd::FigureData, target_object::Any, property::Symbol, value::Any)::Bool
    value === :delete && return false
    redraw = false
    try
        if isa(target_object, Interpolate.RangeControl)
            # Special handling for range control
            UI.update_coord_ranges!(
                fd.ui,
                property,
                value,
                fd.plot_data.update_data_switch,
            )
        elseif isa(target_object, FigureSettings)
            redraw = apply_figure_settings!(fd, property, value)
        elseif isa(target_object, LayerSettings)
            # a plain struct notifies nobody, so re-lay the arrows by hand
            setproperty!(target_object, property, value)
            refresh_vector_density!(fd)
        else
            setproperty!(target_object, property, value)
        end
    catch e
        @warn("Error setting property $property to $value: $e")
    end
    redraw
end

function apply_property_mappings!(fd::FigureData, mappings::Vector{PropertyMapping})::Bool
    redraw = false
    for mapping in mappings
        mapping.current_value == mapping.intended_value && continue
        res = set_property_mapping(fd, mapping.target_object, mapping.property, mapping.intended_value)
        redraw = res ? true : redraw
    end
    redraw
end

function apply_original_property_mappings!(fd::FigureData, mappings::Vector{PropertyMapping})::Bool
    redraw = false
    for mapping in mappings
        res = set_property_mapping(fd, mapping.target_object, mapping.property, mapping.current_value)
        redraw = res ? true : redraw
    end
    redraw
end

function wait_for_n_cycles(fig::Figure, n::Int)::Nothing
    # wait maximum 2 seconds
    tick_count = 0
    starttime = time()
    timeout = 2.0
    on(fig.scene.events.tick) do tick
        tick_count += 1
    end
    while tick_count < n && (time() - starttime) < timeout
        yield()
        sleep(0.01)
    end
    nothing
end

function kwarg_dict_to_string(kwargs::OrderedDict{Symbol, Any})::String
    isempty(kwargs) && return ""
    parts = String[]
    for (k,v) in kwargs
        if isa(v, AbstractString)
            push!(parts, "$k=\"$v\"")
        elseif isa(v, Symbol)
            push!(parts, "$k=:$v")
        else
            push!(parts, "$k=$v")
        end
    end
    join(parts, ", ")
end

"""
    rewrite_kwargs!(fd, kwargs)

Replace the stored keywords without applying anything. The store is
updated first, so the textbox's own diffing finds nothing to do -- which
is what layer removal needs: the layer the dropped keywords named is gone,
so there is nothing left to revert them on.
"""
function rewrite_kwargs!(fd::FigureData,
                         kwargs::OrderedDict{Symbol, Any})::Nothing
    fd.ui.state.kwargs[] = kwargs
    textbox = fd.ui.main_menu.plot_menu.plot_kw
    text = kwarg_dict_to_string(kwargs)
    try
        textbox.displayed_string = isempty(text) ? " " : text
        textbox.stored_string = text
    catch e
        @warn "Error parsing additional arguments: $e"
    end
    nothing
end

function update_kwargs!(fd::FigureData, new_kwargs::OrderedDict{Symbol, Any})::Nothing
    old_kwargs = fd.ui.state.kwargs[]

    diff_kwargs = OrderedDict{Symbol, Any}()
    # Loop over new_kwargs and filter out those that are the same in old_kwargs
    for (k, v) in new_kwargs
        if haskey(old_kwargs, k) && haskey(new_kwargs, k) && old_kwargs[k] == new_kwargs[k]
            continue
        end
        diff_kwargs[k] = v
    end
    # We store kwargs that were removed as well, with value :delete
    for (k, v) in old_kwargs
        if !haskey(new_kwargs, k)
            diff_kwargs[k] = :delete
        end
    end
    # Update the stored kwargs
    fd.ui.state.kwargs[] = new_kwargs
    apply_kwargs!(fd, diff_kwargs)
end

function on_kwarg_string_update(fd::FigureData, kw_str::Union{String, Nothing})::Nothing
    kw_str = isnothing(kw_str) ? "" : kw_str
    new_kwargs = Parsing.parse_kwargs(kw_str)
    update_kwargs!(fd, new_kwargs)
end

function apply_kwargs!(fig_data::FigureData, kwargs::OrderedDict{Symbol, Any})::Nothing
    isempty(kwargs) && return nothing
    # Wait for all previous tasks to complete
    while !all(istaskdone, fig_data.tasks[])
        yield()
    end
    fig_data.tasks[] = Task[]

    mappings = get_property_mappings(kwargs, fig_data)

    # task = @async begin
        output = @capture_err begin
            # @warn "Applying keyword arguments: $kw_str"
            redraw = apply_property_mappings!(fig_data, mappings)
            redraw && redraw!(fig_data)

            # Check if the window is open
            if fig_data.fig.scene.events.window_open[]
                # Wait for 2 render cycles
                wait_for_n_cycles(fig_data.fig, 2)
            end
        end
        if !isempty(output)
            # the revert is all-or-nothing: a value that only fails at
            # render time cannot be blamed on a single keyword. Name
            # everything that goes back, so a setting rolled back
            # because a neighbor failed is never silent.
            # the keys as written, prefixes included: that is what the
            # store is keyed by, and what the user has to retype
            reverted = unique(mapping.key for mapping in mappings)
            @warn ("An error occurred while applying keyword arguments, " *
                   "reverting: " * join(reverted, ", "))
            # Only show the first 5 lines of the error
            lines = split(output, '\n')
            for line in lines[1:min(end, 5)]
                # print the line to stderr
                println(stderr, line)
            end
            # revert to original properties
            for mapping in mappings
                fig_data.ui.state.kwargs[][mapping.key] = mapping.current_value
            end

            redraw = apply_original_property_mappings!(fig_data, mappings)
            redraw && redraw!(fig_data)
        end
    # end
    # push!(fig_data.tasks[], task)
    # kwargs may have changed the colorrange mode or the fixed indices
    update_colorrange!(fig_data)
    nothing
end

function shorten_float(value::Number)::Number
    parse(Float64, @sprintf("%g", value))
end

function get_limit_string(ax::Makie.AbstractAxis)::Tuple
    lim_rect = ax.finallimits[]
    limits = Float64[]
    # Loop through each dimension
    for dim in 1:length(lim_rect.origin)
        # Add min limit (origin)
        push!(limits, lim_rect.origin[dim])
        # Add max limit (origin + width)
        push!(limits, lim_rect.origin[dim] + lim_rect.widths[dim])
    end

    Tuple(shorten_float(value) for value in limits)
end

function fix_figure_kwargs!(fd::FigureData)::Nothing
    textbox = fd.ui.main_menu.plot_menu.plot_kw
    kwargs = copy(fd.ui.state.kwargs[])

    # figsize
    figwidths = fd.fig.scene.viewport[].widths
    figsize = (figwidths[1], figwidths[2])
    if figsize != Constants.FIGSIZE
        kwargs[:figsize] = (figwidths[1], figwidths[2])
    end

    # axis limits
    ax = fd.ax[]
    if !isnothing(ax)
        kwargs[:limits] = get_limit_string(ax)
    end

    # 3D axis orientation
    if ax isa Axis3
        kwargs[:azimuth] = shorten_float(ax.azimuth[])
        kwargs[:elevation] = shorten_float(ax.elevation[])
    end

    new_kw_string = kwarg_dict_to_string(kwargs)
    new_display_string = isempty(new_kw_string) ? " " : new_kw_string

    try
        textbox.displayed_string = new_display_string
        textbox.stored_string = new_kw_string
    catch e
        @warn "Error parsing additional arguments: $e"
        return nothing
    end

    nothing
end

# ============================================================
#  Auto-interpolate
# ============================================================

function update_interpolate!(fd::FigureData)::Nothing
    isnothing(fd.ax[]) && return nothing
    fd.plot_data.plot_type[].type ∉ Constants.GEOGRAPHIC_PLOT_TYPES && return nothing
    # Get the names of x and y coordinates
    x_name = fd.ui.state.x_name[]
    y_name = fd.ui.state.y_name[]
    # Get the dataset
    dataset = fd.plot_data.dataset
    # Get current axis limits
    limits = fd.ax[].finallimits[]
    xmin, xmax = limits.origin[1], limits.origin[1] + limits.widths[1]
    ymin, ymax = limits.origin[2], limits.origin[2] + limits.widths[2]
    # Get data limits
    xlims = Data.get_data_limits(dataset, x_name)
    ylims = Data.get_data_limits(dataset, y_name)
    # Adjust limits if they exceed data limits
    xmin = max(xmin, xlims[1])
    xmax = min(xmax, xlims[2])
    ymin = max(ymin, ylims[1])
    ymax = min(ymax, ylims[2])
    # Get the size of the axis in pixels
    widths = fd.ax[].scene.viewport[].widths
    # Update the coordinate ranges by setting the kwargs in the UI state
    current_kwargs = fd.ui.state.kwargs[]
    new_kwargs = Dict(
        Symbol(x_name) => (xmin, xmax, widths[1]),
        Symbol(y_name) => (ymin, ymax, widths[2]),
    )
    merged_kwargs = merge(current_kwargs, new_kwargs)
    # Update the UI text box with the new kwargs
    textbox = fd.ui.main_menu.plot_menu.plot_kw
    new_kw_string = Plotting.kwarg_dict_to_string(merged_kwargs)
    new_display_string = isempty(new_kw_string) ? " " : new_kw_string
    try
        textbox.displayed_string = new_display_string
        textbox.stored_string = new_kw_string
    catch e
        @warn "Error parsing additional arguments: $e"
    end
    nothing
end

# ============================================================
#  Fill up plot functions
# ============================================================
function compute_aspect(
    kwargs::OrderedDict{Symbol, Any},
    x::AbstractArray,
    y::AbstractArray,
    figwidths::Vec{2, Int},
)::Float64
    # check if aspect is set in kwargs
    if haskey(kwargs, :aspect)
        val = kwargs[:aspect]
        if isa(val, Number) && isfinite(val) && val > 0
            return val
        end
    end
    # compute aspect from data
    x_ext = maximum(x) - minimum(x)
    y_ext = maximum(y) - minimum(y)
    ratio = x_ext / y_ext
    ratio > 0.25 && ratio < 5 && return ratio
    # compute default aspect from figure size
    figwidths[1] / figwidths[2]
end

function compute_aspect2d(fd::FigureData, x::AbstractArray, y::AbstractArray)::Union{Float64, Nothing}
    fd.plot_data.plot_type[].ndims != 2 && return nothing
    # check if aspect is set in kwargs
    kwargs = fd.ui.state.kwargs[]
    figwidths = fd.fig.scene.viewport[].widths
    compute_aspect(kwargs, x, y, figwidths)
end

function compute_aspect(
    kwargs::OrderedDict{Symbol, Any},
    ndims::Int,
    x::AbstractArray,
    y::AbstractArray,
    z::AbstractArray
)::Tuple{Float64, Float64, Float64}
    if haskey(kwargs, :aspect)
        val = kwargs[:aspect]
        if isa(val, Tuple{<:Number, <:Number, <:Number})
            return (Float64(val[1]), Float64(val[2]), Float64(val[3]))
        elseif isa(val, Number) && isfinite(val) && val > 0
            return (1, 1, Float64(val))
        end
    end
    exts = [maximum(xi) - minimum(xi) for xi in (x, y, z)]
    exts = [ext == 0 ? 1.0 : ext for ext in exts]
    ratio = [exts[1] / exts[2], exts[2] / exts[2], exts[3] / exts[2]]
    ratio = [r > 5 || r < 0.25 ? 1 : r for (i, r) in enumerate(ratio)]
    if ndims == 2
        ratio[3] = 0.4
    end
    Tuple(ratio)
end

function compute_aspect3d(fd::FigureData, x::AbstractArray, y::AbstractArray, z::AbstractArray)::Tuple{Float64, Float64, Float64}
    compute_aspect(fd.ui.state.kwargs[], fd.plot_data.plot_type[].ndims, x, y, z)
end

const OPT_FLOAT = Union{Float64, Nothing}

function compute_2d_limits_from_data(
    kwargs::OrderedDict{Symbol, Any},
    x::AbstractArray,
    y::AbstractArray,
)::Tuple{OPT_FLOAT, OPT_FLOAT, OPT_FLOAT, OPT_FLOAT}
    if haskey(kwargs, :limits)
        val = kwargs[:limits]
        length(val) == 4 && return val
    end
    x_min = minimum(x)
    x_max = maximum(x)
    if x_min == x_max
        x_min = nothing
        x_max = nothing
    end
    y_min = minimum(y)
    y_max = maximum(y)
    if y_min == y_max
        y_min = nothing
        y_max = nothing
    end
    (x_min, x_max, y_min, y_max)
end

function compute_2d_limits(fd::FigureData)::Observable{Tuple{OPT_FLOAT, OPT_FLOAT, OPT_FLOAT, OPT_FLOAT}}
    limits = Observable{Tuple{OPT_FLOAT, OPT_FLOAT, OPT_FLOAT, OPT_FLOAT}}(
        compute_2d_limits_from_data(fd.ui.state.kwargs[], fd.plot_data.x[], fd.plot_data.y[]))
    # The updater caused an error, so we disable it for now
    # for trigger in (fd.plot_data.x, fd.plot_data.y)
    #     on(trigger) do _
    #         new_limits = compute_2d_limits_from_data(fd.ui.state.kwargs[], fd.plot_data.x[], fd.plot_data.y[])
    #         limits[] = new_limits
    #     end
    # end
    limits
end


# ============================================================
#  Axis display units
# ============================================================
#
# xunit/yunit/zunit render an axis in another unit of its coordinate's
# family (meters shown as km) without touching the data: tick positions
# are chosen in *display* space -- so they land on round display values
# even for factors like 60 s/min -- and mapped back to native
# coordinates for placement; only the tick strings and the unit bracket
# of the label change. Limits, ranges, and the data inspector stay in
# native units.

"Tick locator rendering a native-unit axis in a converted display unit."
struct UnitTicks
    factor::Float64  # native value * factor == displayed value
end

function Makie.get_ticks(t::UnitTicks, scale, formatter, vmin, vmax)
    display_values = Makie.get_tickvalues(
        Makie.automatic, scale, vmin * t.factor, vmax * t.factor)
    # The automatic formatter labels the round display values directly; a
    # user formatter keeps Makie's semantics and receives native values.
    labels = formatter isa Makie.Automatic ?
        Makie.get_ticklabels(Makie.automatic, display_values) :
        Makie.get_ticklabels(formatter, display_values ./ t.factor)
    (display_values ./ t.factor, labels)
end

"The native-to-display factor for one axis, or nothing when off."
function axis_unit_factor(fd::FigureData, dim_name::String,
                          target::Union{Nothing, String})::Union{Float64, Nothing}
    target === nothing && return nothing
    native = RescaleUnits.get_unit(fd.plot_data.dataset.ds, dim_name)
    RescaleUnits.display_factor(native, target)
end

"Constructor kwargs (xticks = UnitTicks(...), ...) for the active conversions."
function unit_ticks_kwargs(fd::FigureData)::NamedTuple
    state = fd.ui.state
    ndims = fd.plot_data.plot_type[].ndims
    axes = [(:xticks, state.x_name, fd.settings.xunit)]
    # beyond ndims the axis shows the variable, not a coordinate
    ndims > 1 && push!(axes, (:yticks, state.y_name, fd.settings.yunit))
    ndims > 2 && push!(axes, (:zticks, state.z_name, fd.settings.zunit))
    pairs = Pair{Symbol, Any}[]
    for (key, name_obs, unit_obs) in axes
        factor = axis_unit_factor(fd, name_obs[], unit_obs[])
        factor === nothing && continue
        push!(pairs, key => UnitTicks(factor))
    end
    (; pairs...)
end

function create_regular_2d_axis(fd::FigureData)::Axis
    aspect = Observable{Any}(compute_aspect2d(fd, fd.plot_data.x[], fd.plot_data.y[]))
    for trigger in (fd.plot_data.x, fd.plot_data.y)
        on(trigger) do _
            aspect[] = compute_aspect2d(fd, fd.plot_data.x[], fd.plot_data.y[])
        end
    end

    ax = Axis(
        fd.fig[2, 1];
        xlabel = fd.plot_data.labels.xlabel,
        ylabel = fd.plot_data.plot_type[].ndims > 1 ? fd.plot_data.labels.ylabel : "",
        aspect = aspect,
        limits = compute_2d_limits(fd),
        unit_ticks_kwargs(fd)...,
    )

    # Enable moveable by default except if explicitly disabled
    if fd.settings.moveable[] !== false
        enable_movable(ax)
    end
    ax
end

function create_geographic_2d_axis(fd::FigureData)::GeoAxis

    ax = if fd.settings.proj[] === nothing
        GeoAxis(
            fd.fig[2, 1],
            xlabel = fd.plot_data.labels.xlabel,
            ylabel = fd.plot_data.labels.ylabel,
            limits = compute_2d_limits(fd),
        )
    else
        GeoAxis(
            fd.fig[2, 1],
            xlabel = fd.plot_data.labels.xlabel,
            ylabel = fd.plot_data.labels.ylabel,
            dest = fd.settings.proj[],
            limits = compute_2d_limits(fd),
        )
    end

    # Disable moveable by default except if explicitly enabled
    if fd.settings.moveable[] !== true
        disable_movable(ax)
    end
    ax
end

function support_geographic(fd::FigureData)::Bool
    # First we check if the plot type allows for geographic plotting
    fd.plot_data.plot_type[].type ∉ Constants.GEOGRAPHIC_PLOT_TYPES && return false
    # Then we check if the selected x and y dimensions are longitude and latitude
    dataset = fd.range_control[].interp.ds
    x_name = RescaleUnits.get_standard_name(fd.ui.state.x_name[], dataset)
    y_name = RescaleUnits.get_standard_name(fd.ui.state.y_name[], dataset)
    x_name == "longitude" && y_name == "latitude" && return true
    false
end

function create_2d_axis(fd::FigureData)::Union{Axis, GeoAxis}
    is_geo = fd.settings.geographic[] && support_geographic(fd)
    is_geo ? create_geographic_2d_axis(fd) : create_regular_2d_axis(fd)
end

function create_3d_axis(fd::FigureData)::Axis3
    plot_data = fd.plot_data
    ax_layout = fd.fig[2, 1]

    Axis3(
        ax_layout;
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.labels.ylabel,
        zlabel = plot_data.plot_type[].ndims > 2 ? plot_data.labels.zlabel : "",
        aspect = @lift(compute_aspect3d(
            fd, $(fd.plot_data.x), $(fd.plot_data.y), $(fd.plot_data.z))
        ),
        unit_ticks_kwargs(fd)...,
    )
end

function custom_heatmap!(ax, x, y, z, d)
    if ax isa GeoAxis
        surface!(ax, x, y, d; colormap = :balance, inspectable=false, shading = NoShading)
    else
        heatmap!(ax, x, y, d; colormap = :balance, inspectable=false)
    end
end

# ============================================================
#  Vector plots
# ============================================================
#
# `quiver` and `streamplot` draw two components of one field. The arrows
# thin the grid down to a *target* number per axis rather than a fixed
# stride: Ctrl-I (`update_interpolate!`) rewrites the grid to the axis'
# pixel resolution, so a stride's arrow count would grow with the window
# while a target count stays where the user put it. `every=n` picks exact
# grid points for the cases where that is what you want. Streamlines
# follow the field rather than sampling it, so neither applies to them --
# their line count is Makie's own `density`.
#
# On a map the arrows are drawn in lon/lat and projected afterwards, which
# needs two fixes a plain axis does not: an arrow whose tip crosses the
# ±180 seam has that tip projected onto the opposite map edge and draws a
# streak across the whole figure, and the meridians converging toward the
# poles would shrink a constant eastward wind into nothing.

"Grid indices a vector plot samples: a target count, or an exact stride."
function decimation_indices(n::Int, target::Int,
                            every::Union{Nothing, Int})::StepRange{Int, Int}
    n <= 0 && return 1:1:0
    every !== nothing && every >= 1 && return 1:every:n
    target <= 0 && return 1:1:n
    1:max(1, cld(n, target)):n
end

"""
    any_finite_vector(u, v)

Whether any grid point carries a finite vector at all. A slab that is
missing everywhere (a masked ocean level, say) has nothing to draw, and
handing it on would leave the colorbar without a single tick to place.
"""
function any_finite_vector(u, v)::Bool
    usable(value) = value isa Number && isfinite(value)
    for k in eachindex(u)
        (usable(u[k]) && usable(v[k])) && return true
    end
    false
end

"The `p`-quantile of the finite values in `values`, or 0 without any."
function finite_quantile(values::AbstractArray, p::Float64)::Float64
    finite = Float64[v for v in values if isfinite(v)]
    isempty(finite) && return 0.0
    sort!(finite)
    finite[clamp(ceil(Int, p * length(finite)), 1, length(finite))]
end

"One frame of a vector field, thinned down to what actually gets drawn."
struct VectorField
    x::Vector{Float64}
    y::Vector{Float64}
    u::Matrix{Float64}
    v::Matrix{Float64}
    # |V| per sample, in the column-major order arrows2d! draws them in
    magnitude::Vector{Float64}
    lengthscale::Float64
end

"""
The stand-in for "nothing to draw" -- no partner selected, or a grid and
a field that do not line up (yet). It is not empty: Makie cannot build an
arrow mesh out of zero arrows at all, and a colorbar over a single
repeated value finds no ticks and says so on stderr, which would trip the
kwargs path's revert machinery. Two samples spanning 0..1 keep both out
of their degenerate corners, and the plot is hidden while this is what it
holds.
"""
const EMPTY_VECTOR_FIELD = VectorField([0.0, 1.0], [0.0], zeros(2, 1),
                                       zeros(2, 1), [0.0, 1.0], 1.0)

"""
    wraps_globally(x)

Whether a longitude axis closes on itself, so that its two edges are the
same meridian and there is a seam for an arrow to cross. A global grid
stops one cell short of a full turn -- its last point is not a repeat of
its first -- so what has to close the circle is the span *plus one cell*,
which is what keeps a coarse 30-degree global grid global.
"""
function wraps_globally(x)::Bool
    n = length(x)
    n >= 2 || return false
    span = Float64(maximum(x)) - Float64(minimum(x))
    span + span / (n - 1) >= Constants.GLOBAL_LONGITUDE_SPAN
end

"""
    mask_outside_domain!(x, y, u, v, lengthscale, xlim, ylim)

Blank every arrow whose tip leaves the drawn domain. Past the ±180 seam
the projection throws the tip onto the opposite map edge, which draws a
streak clean across the figure; a NaN direction drops the arrow instead.
Only worth doing on a domain that has such a seam -- see `wraps_globally`.
"""
function mask_outside_domain!(x::Vector{Float64}, y::Vector{Float64},
                              u::Matrix{Float64}, v::Matrix{Float64},
                              lengthscale::Float64,
                              xlim::Tuple{Float64, Float64},
                              ylim::Tuple{Float64, Float64})::Nothing
    for j in eachindex(y), i in eachindex(x)
        tipx = x[i] + lengthscale * u[i, j]
        tipy = y[j] + lengthscale * v[i, j]
        if !(xlim[1] <= tipx <= xlim[2]) || !(ylim[1] <= tipy <= ylim[2])
            u[i, j] = NaN
            v[i, j] = NaN
        end
    end
    nothing
end

"""
    decimate_vector_field(x, y, u, v, target, every, geographic)

Thin a vector field down to the arrows that get drawn and derive their
length scale. Returns the empty field whenever the inputs do not line up:
`x`, `y` and the data arrive in separate observable notifications, so a
lift over them transiently sees a grid and a field of different shapes.
"""
function decimate_vector_field(
    x, y, u, v,
    target::Tuple{Int, Int}, every::Union{Nothing, Int}, geographic::Bool,
)::VectorField
    any(isnothing, (x, y, u, v)) && return EMPTY_VECTOR_FIELD
    nx, ny = length(x), length(y)
    (nx >= 2 && ny >= 2) || return EMPTY_VECTOR_FIELD
    (size(u) == (nx, ny) && size(v) == (nx, ny)) || return EMPTY_VECTOR_FIELD
    ix = decimation_indices(nx, target[1], every)
    iy = decimation_indices(ny, target[2], every)
    dx = Float64[x[i] for i in ix]
    dy = Float64[y[j] for j in iy]
    # indexing with the strides already copies, so these are ours to
    # correct and mask in place
    du = convert(Matrix{Float64}, u[ix, iy])
    dv = convert(Matrix{Float64}, v[ix, iy])
    any_finite_vector(du, dv) || return EMPTY_VECTOR_FIELD
    # the colors are the *physical* magnitudes, taken before the
    # projection correction below inflates the zonal component
    magnitude = vec(hypot.(du, dv))
    # a high percentile rather than the maximum: a single outlier gust
    # would otherwise shrink the whole field into invisibility
    reference = finite_quantile(magnitude, Constants.VECTOR_SCALE_QUANTILE)
    reference > 0 || (reference = 1.0)
    cellx = length(dx) > 1 ? abs(dx[2] - dx[1]) : 1.0
    celly = length(dy) > 1 ? abs(dy[2] - dy[1]) : 1.0
    lengthscale = Constants.VECTOR_ARROW_FILL * min(cellx, celly) / reference
    if geographic
        # a degree of longitude covers cos(latitude) of the distance a
        # degree of latitude does, so an eastward wind has to be spread
        # over that many more degrees to keep its drawn length; the floor
        # stops the arrows next to the poles from blowing up
        for j in eachindex(dy), i in eachindex(dx)
            du[i, j] /= max(cosd(dy[j]), Constants.COS_LATITUDE_FLOOR)
        end
        # a regional cut-out has no seam to cross, and masking it would
        # only punch holes along its own borders
        wraps_globally(x) && mask_outside_domain!(
            dx, dy, du, dv, lengthscale,
            extrema(Float64, x), extrema(Float64, y))
    end
    VectorField(dx, dy, du, dv, magnitude, lengthscale)
end

"""
    vector_field_observable(fd, ax, i, x, y, u, v)

The drawn field of layer `i`, kept in step with the grid and both data
components. Reads the density settings without subscribing to them, so
changing one costs a `notify` on the data (see `refresh_vector_density!`)
instead of a listener that outlives the plot.
"""
function vector_field_observable(fd::FigureData, ax::Makie.AbstractAxis,
                                 i::Int, x::Observable, y::Observable,
                                 u::Observable, v::Observable,
                                 )::Observable{VectorField}
    geographic = ax isa GeoAxis
    field = Observable(EMPTY_VECTOR_FIELD)
    update = (xs, ys, us, vs) -> begin
        field[] = decimate_vector_field(
            xs, ys, us, vs, layer_arrows(fd, i), layer_every(fd, i),
            geographic)
    end
    update(x[], y[], u[], v[])
    onany(update, x, y, u, v)
    field
end

function quiver_plot!(fd::FigureData, ax::Makie.AbstractAxis, i::Int,
                      x::Observable, y::Observable,
                      u::Observable, v::Observable)
    field = vector_field_observable(fd, ax, i, x, y, u, v)
    # arrows2d!, not the deprecated arrows!: the shim warns, and a stray
    # write to stderr trips the kwargs path's revert machinery
    arrows2d!(ax,
        @lift($field.x), @lift($field.y), @lift($field.u), @lift($field.v);
        lengthscale = @lift($field.lengthscale),
        color = @lift($field.magnitude),
        visible = @lift($field !== EMPTY_VECTOR_FIELD),
        colormap = Constants.VECTOR_COLORMAP, inspectable = false)
end

"""
Bilinear sampler over a regular grid, in the shape `streamplot!` wants.
It only accepts a `Function` -- a plain callable struct is taken silently
and then fails deep inside the compute graph with a length error -- so
this is declared as one. Being a named type it also precompiles, which an
anonymous closure would not.
"""
struct GridField <: Function
    x::Vector{Float64}
    y::Vector{Float64}
    u::Matrix{Float64}
    v::Matrix{Float64}
end

function (field::GridField)(p)
    nx, ny = length(field.x), length(field.y)
    (nx >= 2 && ny >= 2) || return Point2f(0, 0)
    spanx = field.x[end] - field.x[1]
    spany = field.y[end] - field.y[1]
    (isfinite(spanx) && spanx != 0 && isfinite(spany) && spany != 0) ||
        return Point2f(0, 0)
    tx = (p[1] - field.x[1]) / spanx * (nx - 1)
    ty = (p[2] - field.y[1]) / spany * (ny - 1)
    (isfinite(tx) && isfinite(ty)) || return Point2f(0, 0)
    i = clamp(floor(Int, tx) + 1, 1, nx - 1)
    j = clamp(floor(Int, ty) + 1, 1, ny - 1)
    fx = clamp(tx - (i - 1), 0.0, 1.0)
    fy = clamp(ty - (j - 1), 0.0, 1.0)
    w11 = (1 - fx) * (1 - fy)
    w21 = fx * (1 - fy)
    w12 = (1 - fx) * fy
    w22 = fx * fy
    Point2f(
        w11 * field.u[i, j] + w21 * field.u[i + 1, j] +
            w12 * field.u[i, j + 1] + w22 * field.u[i + 1, j + 1],
        w11 * field.v[i, j] + w21 * field.v[i + 1, j] +
            w12 * field.v[i, j + 1] + w22 * field.v[i + 1, j + 1],
    )
end

# The stand-in for "nothing to draw", for the same reasons as
# EMPTY_VECTOR_FIELD: a constant field colors every streamline alike,
# which leaves the colorbar without ticks and writing to stderr. The
# ramp along x spans a range instead; the plot is hidden meanwhile.
const EMPTY_GRID_FIELD = GridField([0.0, 1.0], [0.0, 1.0],
                                   [0.0 0.0; 1.0 1.0], zeros(2, 2))

"""
    grid_field_state(x, y, u, v)

Everything `streamplot!` needs for one frame -- the sampler, the domain
it integrates in, and a step derived from that domain -- or nothing when
the inputs do not line up. `x`, `y` and the data arrive in separate
observable notifications, so this transiently sees shapes that do not
match, and a slab that is missing everywhere has nothing to follow.
"""
function grid_field_state(x, y, u,
                          v)::Union{Nothing, Tuple{GridField, Rect2{Float64},
                                                   Float64}}
    any(isnothing, (x, y, u, v)) && return nothing
    nx, ny = length(x), length(y)
    (nx >= 2 && ny >= 2) || return nothing
    (size(u) == (nx, ny) && size(v) == (nx, ny)) || return nothing
    any_finite_vector(u, v) || return nothing
    gx = convert(Vector{Float64}, x)
    gy = convert(Vector{Float64}, y)
    spanx = gx[end] - gx[1]
    spany = gy[end] - gy[1]
    (isfinite(spanx) && spanx != 0 && isfinite(spany) && spany != 0) ||
        return nothing
    # `convert`, not the constructor: the streamlines read the full grid,
    # and a copy of it per animation frame is not free. Nothing mutates
    # these, and `get_data` hands out a fresh array every time anyway.
    (GridField(gx, gy, convert(Matrix{Float64}, u), convert(Matrix{Float64}, v)),
     Rect2(min(gx[1], gx[end]), min(gy[1], gy[end]), abs(spanx), abs(spany)),
     min(abs(spanx), abs(spany)) / Constants.STREAMPLOT_STEPS)
end

"""
    streamplot_plot!(fd, ax, x, y, u, v)

Streamlines of the field. They sample the full grid rather than the
thinned one the arrows use -- how many lines are drawn is Makie's own
`density`, not a grid stride -- and they skip the geographic corrections:
the lines are not scaled to a drawn length, `limits` already ends a line
that reaches the ±180 seam, and the cos(latitude) factor would inflate
exactly the magnitudes their color comes from.
"""
function streamplot_plot!(fd::FigureData, ax::Makie.AbstractAxis,
                          x::Observable, y::Observable,
                          u::Observable, v::Observable)
    sampler = Observable(EMPTY_GRID_FIELD)
    limits = Observable(Rect2(0.0, 0.0, 1.0, 1.0))
    # Makie's default stepsize (0.01) is in data units: on a lon/lat grid
    # every step would travel 5 degrees and maxsteps would cut the line
    # off after a handful of them
    stepsize = Observable(0.01)
    live = Observable(false)
    update = (xs, ys, us, vs) -> begin
        state = grid_field_state(xs, ys, us, vs)
        if state === nothing
            live[] = false
            return
        end
        sampler[], limits[], stepsize[] = state
        live[] = true
    end
    update(x[], y[], u[], v[])
    onany(update, x, y, u, v)
    streamplot!(ax, sampler, limits;
        stepsize = stepsize, gridsize = Constants.STREAMPLOT_GRIDSIZE,
        visible = live,
        colormap = Constants.VECTOR_COLORMAP, inspectable = false)
end


for plot in [
    # 2D plots
    Plot("heatmap", 2, true,
        (fd, ax, i, x, y, z, d) -> custom_heatmap!(ax, x, y, z, d),
        create_2d_axis),
    Plot("contour", 2, false,
        (fd, ax, i, x, y, z, d) -> contour!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_2d_axis),
    Plot("contourf", 2, true,
        (fd, ax, i, x, y, z, d) -> contourf!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_2d_axis),
    Plot("surface", 2, true,
        (fd, ax, i, x, y, z, d) -> surface!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_3d_axis; axis_kind = :ax3d),
    Plot("wireframe", 2, false,
        (fd, ax, i, x, y, z, d) -> wireframe!(ax, x, y, d, color = :royalblue3, inspectable=false),
        create_3d_axis; axis_kind = :ax3d),

    # 2D vector plots (two components)
    Plot("quiver", 2, true,
        (fd, ax, i, x, y, z, u, v) -> quiver_plot!(fd, ax, i, x, y, u, v),
        create_2d_axis; nfields = 2),
    Plot("streamplot", 2, true,
        (fd, ax, i, x, y, z, u, v) -> streamplot_plot!(fd, ax, x, y, u, v),
        create_2d_axis; nfields = 2),

    # 1D plots
    Plot("line", 1, false,
        (fd, ax, i, x, y, z, d) -> lines!(ax, x, d, color = :royalblue3, inspectable=false, linestyle = :solid),
        create_2d_axis),
    Plot("scatter", 1, false,
        (fd, ax, i, x, y, z, d) -> scatter!(ax, x, d, color = :royalblue3, inspectable=false),
        create_2d_axis),

    # 3D plots
    Plot("volume", 3, true,
        (fd, ax, i, x, y, z, d) -> volume!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance),
        create_3d_axis; axis_kind = :ax3d),
    Plot("contour3d", 3, true,
        (fd, ax, i, x, y, z, d) -> contour!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance),
        create_3d_axis; axis_kind = :ax3d),
]
    PLOT_TYPES[plot.type] = plot
end


end