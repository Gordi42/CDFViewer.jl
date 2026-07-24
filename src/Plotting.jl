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
end

const PLOT_TYPES = OrderedDict(plot.type => plot for plot in [
    Plot(Constants.NOT_SELECTED_LABEL, 0, false,
        (ax, x, y, z, d) -> nothing,
        (fd) -> nothing),
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
        Observable{Union{Nothing, String}}(nothing),      # xunit
        Observable{Union{Nothing, String}}(nothing),      # yunit
        Observable{Union{Nothing, String}}(nothing),      # zunit
        Observable(0.0),                                  # rotate
        Observable(0.0),                                  # rotatev
        Observable{Union{Nothing, NTuple{2, Float64}}}(nothing),  # rotatelim
        Observable((0.0, 80.0)),                          # rotatevlim
    )
end

# ============================================================
#  Figure labels
# ============================================================

struct FigureLabels
    title::Observable{String}
    xlabel::Observable{String}
    ylabel::Observable{String}
    zlabel::Observable{String}
end

function FigureLabels(ui_state::UI.State, dataset::Data.CDFDataset,
                      settings::FigureSettings)::FigureLabels
    title = @lift(Data.get_label(dataset, $(ui_state.variable)))
    xlabel = @lift(Data.get_label(dataset, $(ui_state.x_name);
                                  target_unit = $(settings.xunit)))
    ylabel = @lift(Data.get_label(dataset, $(ui_state.y_name);
                                  target_unit = $(settings.yunit)))
    zlabel = @lift(Data.get_label(dataset, $(ui_state.z_name);
                                  target_unit = $(settings.zunit)))
    FigureLabels(title, xlabel, ylabel, zlabel)
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

"Measured pixel width of `s` at the given fontsize."
measure_text(s::String, fontsize::Real = Constants.LABELSIZE)::Float64 =
    isempty(s) ? 0.0 : Float64(Makie.widths(
        Makie.text_bb(s, animlabel_font(), Float64(fontsize)))[1])

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

struct PlotData
    plot_type::Observable{Plot}
    sel_dims::Observable{Vector{String}}
    x::Observable{Union{Array, Nothing}}
    y::Observable{Union{Array, Nothing}}
    z::Observable{Union{Array, Nothing}}
    d::Vector{Observable{Union{Array, Nothing}}}
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
    # Observable for the data array
    d = [Observable{Union{Array, Nothing}}(nothing) for _ in 1:3] # max 3D data

    # Set up listeners to update the data array when relevant observables change
    for trigger in (ui_state.variable, sel_dims, ui_state.dim_obs, update_switch)
        on(trigger) do _
            !(update_switch[]) && return
            ndims = length(sel_dims[])
            ndims == 0 && return
            d[ndims][] = Data.get_data(
                dataset, ui_state.variable[], sel_dims[], ui_state.dim_obs[])
        end
    end

    # Figure labels
    labels = FigureLabels(ui_state, dataset, settings)

    # Construct and return the PlotData
    PlotData(plot_type, sel_dims, x, y, z, d, update_switch, labels, dataset,
             settings)
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

"Mutable scan state: what is pinned, what is in flight, and past results."
mutable struct ColorRangeScan
    generation::Int                   # bumped to abort superseded scans
    pending_key::Any                  # key of the scan in flight
    applied_key::Any                  # key of the currently applied pin
    task::Union{Nothing, Task}
    cache::Dict{Any, NTuple{2, Float64}}
    base_levels::Union{Nothing, Int}  # the plot's own Int `levels`
    hinted::Bool                      # size-gate hint already shown
end

ColorRangeScan() = ColorRangeScan(0, nothing, nothing, nothing,
                                  Dict{Any, NTuple{2, Float64}}(), nothing,
                                  false)

# ============================================================
#  Figure data structure
# ============================================================

struct FigureData
    fig::Figure
    plot_data::PlotData
    ax::Observable{Union{Makie.AbstractAxis, Nothing}}
    plot_obj::Observable{Union{Makie.AbstractPlot, Nothing}}
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
    crange_scan::ColorRangeScan
    # +1/-1: which way the bouncing camera rotations are heading
    camera_vdir::Base.RefValue{Float64}
    camera_hdir::Base.RefValue{Float64}
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
    plot_obj = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
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
        plot_obj,
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
        ColorRangeScan(),
        Ref(1.0),
        Ref(1.0),
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
    for trigger in (ui_state.variable, plot_data.sel_dims, ui_state.pdim,
                    ui_state.dim_obs)
        on(trigger) do _
            update_colorrange!(fd)
        end
    end

    # Setup a listener to create the plot if the axis changes
    on(ax) do a
        a === nothing && return
        # first we clear the previous plot
        cbar[] !== nothing && delete!(cbar[])
        cbar[] = nothing
        plot_data.plot_type[].type == Constants.NOT_SELECTED_LABEL && return  # TODO

        # then we create the new plot
        plot_obj[] = plot_data.plot_type[].func(
            a, plot_data.x, plot_data.y, plot_data.z,
            plot_data.d[plot_data.plot_type[].ndims])
        # and add a colorbar if needed
        add_colorbar!(fd)
        add_earth!(fd)
        add_land!(fd)
        add_coastlines!(fd)
        rebuild_header!(fd)
        rebuild_overlay!(fd)
        refresh_anim_values!(fd)
        # a fresh plot carries no pin and owns its levels again
        fd.crange_scan.applied_key = nothing
        fd.crange_scan.base_levels = nothing
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
    plt = text!(scene, titlepos; text = fd.title_text,
                align = (:left, :bottom), font = :bold,
                fontsize = fd.settings.titlesize, space = :pixel,
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
    fig_data.ax[] !== nothing && delete!(fig_data.ax[])
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
    if fd.plot_data.plot_type[].colorbar && fd.plot_obj[] !== nothing && fd.settings.cbar[]
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
        fd.cbar[] = Colorbar(fd.fig[2, 2], fd.plot_obj[];
            width = 30, tellwidth = false, tellheight = false, size_kw...)
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
    fd.plot_obj[] = nothing
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

"The colorrange mode of the current kwargs: :manual, or a mode symbol."
function colorrange_mode(fd::FigureData)::Symbol
    value = get(fd.ui.state.kwargs[], :colorrange, nothing)
    value === nothing && return :cycle
    if value isa AbstractString || value isa Symbol
        s = String(value)
        s in CRANGE_MODES && return Symbol(s)
        return :cycle  # invalid mode strings were rejected with an error
    end
    :manual
end

"Whether the user chose the mode (an explicit choice bypasses the gate)."
colorrange_explicit(fd::FigureData)::Bool =
    haskey(fd.ui.state.kwargs[], :colorrange)

"The playback dimension when it is actually animatable, else nothing."
function scan_pdim(fd::FigureData, variable::String)::Union{Nothing, String}
    pdim = fd.ui.state.pdim[]
    pdim == Constants.NOT_SELECTED_LABEL && return nothing
    pdim ∈ fd.plot_data.sel_dims[] && return nothing
    pdim ∈ Data.get_var_dims(fd.plot_data.dataset, variable) || return nothing
    pdim
end

"The hyperslab key the active mode wants pinned, or nothing (autoscale)."
function colorrange_key(fd::FigureData, mode::Symbol)::Any
    state = fd.ui.state
    variable = state.variable[]
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
        DataLimits.scan_indexing(dataset, variable, keep, state.dim_obs[])
    catch
        return nothing
    end
    (variable, Tuple(indexing))
end

# contour plots re-bin an Int `levels` from each frame's extrema, so the
# pin must hand them concrete boundaries; a colorrange alone won't hold
is_contour_type(fd::FigureData)::Bool =
    fd.plot_data.plot_type[].type in ("contour", "contourf", "contour3d")

"The user's `levels` kwarg (an explicit vector always wins over the pin)."
user_levels(fd::FigureData)::Any = get(fd.ui.state.kwargs[], :levels, nothing)

function pin_levels!(fd::FigureData, lo::Float64, hi::Float64)::Nothing
    is_contour_type(fd) || return nothing
    user_levels(fd) isa AbstractVector && return nothing
    plot = fd.plot_obj[]
    (plot === nothing || :levels ∉ propertynames(plot)) && return nothing
    scan = fd.crange_scan
    if scan.base_levels === nothing
        current = plot.levels[]
        current isa Int || return nothing  # someone else owns the levels
        scan.base_levels = current
    end
    count = user_levels(fd) isa Int ? user_levels(fd) : scan.base_levels
    # an Int means band boundaries for contourf, line values for contour
    edges = fd.plot_data.plot_type[].type == "contourf" ? count + 1 : count
    plot.levels[] = collect(range(lo, hi; length = edges))
    nothing
end

"Hand a pinned Int `levels` back to the plot."
function restore_levels!(fd::FigureData)::Nothing
    scan = fd.crange_scan
    scan.base_levels === nothing && return nothing
    plot = fd.plot_obj[]
    if plot !== nothing && :levels ∈ propertynames(plot)
        count = user_levels(fd) isa Int ? user_levels(fd) : scan.base_levels
        plot.levels[] = count
    end
    scan.base_levels = nothing
    nothing
end

"Apply a computed range to the plot, remembering what is pinned."
function apply_colorrange_pin!(fd::FigureData, key::Any,
                               range::NTuple{2, Float64})::Nothing
    plot = fd.plot_obj[]
    plot === nothing && return nothing
    lo, hi = range
    lo == hi && ((lo, hi) = (lo - 0.5, hi + 0.5))  # degenerate data
    fd.crange_scan.applied_key = key
    :colorrange ∈ propertynames(plot) && (plot.colorrange[] = (lo, hi))
    pin_levels!(fd, lo, hi)
    nothing
end

"Return the plot to Makie's own autoscaling and its own levels."
function unpin_colorrange!(fd::FigureData)::Nothing
    fd.crange_scan.applied_key = nothing
    plot = fd.plot_obj[]
    plot === nothing && return nothing
    :colorrange ∈ propertynames(plot) && (plot.colorrange[] = Makie.automatic)
    restore_levels!(fd)
    nothing
end

"""
    update_colorrange!(fd; sync = false)

Reconcile the plot's color range with the active mode. Cheap when
nothing changed (the per-frame path during playback): the target key is
recomputed and compared before any work happens. A cache miss starts a
background scan -- or runs it inline with `sync = true`, which record
uses so a video never rescales mid-file. The previous pin stays applied
until its replacement is ready.
"""
function update_colorrange!(fd::FigureData; sync::Bool = false)::Nothing
    plot = fd.plot_obj[]
    plot === nothing && return nothing
    scan = fd.crange_scan
    mode = colorrange_mode(fd)
    if mode === :manual
        value = fd.ui.state.kwargs[][:colorrange]
        key = (:manual, value)
        key == scan.applied_key && return nothing
        scan.generation += 1
        scan.pending_key = nothing
        # the kwargs path sets the plot's colorrange; only the contour
        # levels need pinning here
        restore_levels!(fd)
        value isa Tuple && length(value) == 2 && all(x -> x isa Real, value) &&
            pin_levels!(fd, Float64(value[1]), Float64(value[2]))
        scan.applied_key = key
        return nothing
    end
    key = mode === :frame ? nothing : colorrange_key(fd, mode)
    key !== nothing && key == scan.applied_key && return nothing
    # The default pin never starts an expensive scan uninvited: past the
    # gate the range stays per-frame until the user explicitly asks.
    if key !== nothing && !haskey(scan.cache, key) && !colorrange_explicit(fd)
        elements = DataLimits.hyperslab_elements(
            fd.plot_data.dataset, key[1], collect(Union{Colon, Int}, key[2]))
        if elements > DataLimits.AUTO_SCAN_ELEMENTS[]
            if !scan.hinted
                scan.hinted = true
                @info ("Automatic color-range pinning skipped: this view " *
                       "spans $elements values. Set colorrange=\"cycle\" " *
                       "to scan anyway, or pin a manual colorrange=(lo, hi).")
            end
            key = nothing
        end
    end
    if key === nothing
        scan.applied_key === nothing && return nothing
        scan.generation += 1
        scan.pending_key = nothing
        unpin_colorrange!(fd)
        return nothing
    end
    if haskey(scan.cache, key)
        scan.generation += 1
        scan.pending_key = nothing
        apply_colorrange_pin!(fd, key, scan.cache[key])
        return nothing
    end
    !sync && key == scan.pending_key && return nothing  # already scanning
    scan.generation += 1
    generation = scan.generation
    scan.pending_key = key
    dataset = fd.plot_data.dataset
    runner = () -> begin
        result = DataLimits.hyperslab_extrema(
            dataset, key[1], collect(Union{Colon, Int}, key[2]);
            abort = () -> scan.generation != generation)
        scan.generation == generation || return
        scan.pending_key = nothing
        result === nothing && return
        scan.cache[key] = result
        apply_colorrange_pin!(fd, key, result)
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

struct PropertyMapping
    property::Symbol
    target_object::Any
    current_value::Any
    intended_value::Any
end

function get_default_value(fd::FigureData, target_object::Any, property::Symbol)::Any
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
            :xunit => nothing,
            :yunit => nothing,
            :zunit => nothing,
            :rotate => 0.0,
            :rotatev => 0.0,
            :rotatelim => nothing,
            :rotatevlim => (0.0, 80.0),
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
    

function get_property_mappings(kwargs::OrderedDict{Symbol, Any}, fig_data::FigureData)::Vector{PropertyMapping}
    mappings = Vector{PropertyMapping}()
    for (property, intended_value) in kwargs
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
        found_targets = 0
        for target_obj in (fig_data.ax[], fig_data.plot_obj[], fig_data.cbar[], fig_data.settings, fig_data.range_control[])
            target_obj === nothing && continue
            # the figure title lives in a layout Label; never touch
            # the axis' native (empty) title
            property in (:title, :titlesize) &&
                target_obj isa Makie.AbstractAxis && continue
            property ∉ propertynames(target_obj) && continue
            
            # Get the current value of the property
            current_value = getproperty(target_obj, property)
            # If it's an Observable, get its value
            current_value = try
                current_value[]
            catch
                current_value  # not an observable
            end

            if intended_value === :delete
                intended_value = get_default_value(fig_data, target_obj, property)
            end

            push!(mappings, PropertyMapping(property, target_obj, current_value, intended_value))
            found_targets += 1
        end
        found_targets == 0 && @warn "Property $property not found in any plot object"
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
            @warn "An error occurred while applying keyword arguments"
            # Only show the first 5 lines of the error
            lines = split(output, '\n')
            for line in lines[1:min(end, 5)]
                # print the line to stderr
                println(stderr, line)
            end
            # revert to original properties
            for mapping in mappings
                fig_data.ui.state.kwargs[][mapping.property] = mapping.current_value
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


for plot in [
    # 2D plots
    Plot("heatmap", 2, true,
        (ax, x, y, z, d) -> custom_heatmap!(ax, x, y, z, d),
        create_2d_axis),
    Plot("contour", 2, false,
        (ax, x, y, z, d) -> contour!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_2d_axis),
    Plot("contourf", 2, true,
        (ax, x, y, z, d) -> contourf!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_2d_axis),
    Plot("surface", 2, true,
        (ax, x, y, z, d) -> surface!(ax, x, y, d, colormap = :balance, inspectable=false),
        create_3d_axis),
    Plot("wireframe", 2, false,
        (ax, x, y, z, d) -> wireframe!(ax, x, y, d, color = :royalblue3, inspectable=false),
        create_3d_axis),

    # 1D plots
    Plot("line", 1, false,
        (ax, x, y, z, d) -> lines!(ax, x, d, color = :royalblue3, inspectable=false, linestyle = :solid),
        create_2d_axis),
    Plot("scatter", 1, false,
        (ax, x, y, z, d) -> scatter!(ax, x, d, color = :royalblue3, inspectable=false),
        create_2d_axis),

    # 3D plots
    Plot("volume", 3, true,
        (ax, x, y, z, d) -> volume!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance),
        create_3d_axis),
    Plot("contour3d", 3, true,
        (ax, x, y, z, d) -> contour!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance),
        create_3d_axis),
]
    PLOT_TYPES[plot.type] = plot
end


end