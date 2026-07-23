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
    # nothing = automatic (the variable label); a string overrides it
    title::Observable{Union{Nothing, String}}
    titlesize::Observable{Float64}
    animlabelsize::Observable{Float64}

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
        Observable(Constants.NUMBER_FORMAT),            # animlabelnumfmt
        Observable(Constants.DATETIME_FORMAT),          # animlabeldateformat
        Observable(Constants.ANIMLABEL_CORNER),         # animlabelcorner
        Observable{Any}(Constants.ANIMLABEL_BACKGROUND),  # animlabelbg
        Observable{Union{Nothing, String}}(nothing),      # title override
        Observable(Float64(Constants.TITLESIZE)),         # titlesize
        Observable(Float64(Constants.LABELSIZE)),         # animlabelsize
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

function FigureLabels(ui_state::UI.State, dataset::Data.CDFDataset)::FigureLabels
    title = @lift(Data.get_label(dataset, $(ui_state.variable)))
    xlabel = @lift(Data.get_label(dataset, $(ui_state.x_name)))
    ylabel = @lift(Data.get_label(dataset, $(ui_state.y_name)))
    zlabel = @lift(Data.get_label(dataset, $(ui_state.z_name)))
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
const ANIM_DYNAMIC_PLACEHOLDER = r"\{(?:value|rawvalue|index)\}"

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
            placeholder::String, numfmt::String, dateformat::String)::String =
    Data.format_dim_label(dataset, pdim, idx; fmt = placeholder,
                          numfmt = numfmt, dateformat = dateformat)

"""
    widest_slot_text(dataset, pdim, placeholder, numfmt, dateformat)

The widest rendering a placeholder can produce over the whole axis
(pixel-measured; long axes are sampled). The slot is sized from it, so the
slot never changes width during playback.
"""
function widest_slot_text(
    dataset::Data.CDFDataset, pdim::String, placeholder::String,
    numfmt::String, dateformat::String,
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
        s = render_slot(dataset, pdim, i, placeholder, numfmt, dateformat)
        w = measure_text(s, fontsize)
        w > wmax && (widest = s; wmax = w)
    end
    widest
end

"""
    compile_animlabel(dataset, variable, sel_dims, pdim, animlabel,
                      numfmt, dateformat)

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
    numfmt::String,
    dateformat::String,
    fontsize::Real = Constants.LABELSIZE,
)::Vector{AnimSegment}
    fmt = animlabel_format(animlabel)
    isempty(fmt) && return AnimSegment[]
    pdim == Constants.NOT_SELECTED_LABEL && return AnimSegment[]
    pdim ∈ sel_dims && return AnimSegment[]
    haskey(dataset.var_coords, variable) || return AnimSegment[]
    pdim ∈ Data.get_var_dims(dataset, variable) || return AnimSegment[]
    # placeholders that cannot change during playback become static text
    fmt = replace(fmt,
        "{name}" => Data.get_dim_display_name(dataset, pdim),
        "{unit}" => Data.get_dim_unit(dataset, pdim))
    static(txt) = AnimSegment("", false, txt, measure_text(txt, fontsize))
    segments = AnimSegment[]
    pos = 1
    for m in eachmatch(ANIM_DYNAMIC_PLACEHOLDER, fmt)
        m.offset > pos &&
            push!(segments, static(fmt[pos:prevind(fmt, m.offset)]))
        widest = widest_slot_text(dataset, pdim, String(m.match),
                                  numfmt, dateformat, fontsize)
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
    labels = FigureLabels(ui_state, dataset)

    # Construct and return the PlotData
    PlotData(plot_type, sel_dims, x, y, z, d, update_switch, labels, dataset,
             settings)
end

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
    # layout-title machinery: title Label row + animated-label row
    title_label::Label
    animrow::GridLayout
    anim_slots::Vector{Observable{String}}
    anim_segments::Base.RefValue{Vector{AnimSegment}}
    anim_overlay::Base.RefValue{Vector{Any}}
end

function FigureData(plot_data::PlotData, ui::UI.UIElements)::FigureData
    ui_state = ui.state
    # one settings object, shared with the labels that lift out of it
    settings = plot_data.settings
    # Create axis, plot object, and colorbar observables
    figsize = Observable(Constants.FIGSIZE)
    fig = create_figure(figsize[])
    # Row 1, the header: the figure title on the left, the animated-axis
    # label on the right of the same row. The native axis title is disabled:
    # a layout Label reserves exactly the height it needs on every axis type
    # (Axis3 reserves a single-line strip only, so a taller native title
    # clips). Row 2: the axis body (+ colorbar).
    header = GridLayout(fig[1, 1])
    title_text = @lift begin
        override = $(settings.title)
        override === nothing ? $(plot_data.labels.title) : override
    end
    title_label = Label(header[1, 1], title_text;
        fontsize = settings.titlesize, font = :bold,
        halign = :left, tellwidth = false)
    animrow = GridLayout(header[1, 2]; tellwidth = true,
                         halign = :right, valign = :bottom)
    # keep a zero-size placeholder: trim! on a contentless layout collapses
    # it to zero rows, whose NaN sizes poison the whole figure solve (an
    # empty-string Label is just as poisonous -- hence the single space)
    Label(animrow[1, 1], " "; fontsize = 1, visible = false)
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
        title_label,
        animrow,
        Observable{String}[],
        Ref(AnimSegment[]),
        Ref(Any[]),
    )

    # Rebuild the animated-axis label when its configuration changes;
    # per-frame value updates only touch the slot text observables.
    for trigger in (ui_state.variable, plot_data.sel_dims, ui_state.pdim,
                    settings.animlabel, settings.animlabelnumfmt,
                    settings.animlabeldateformat, settings.animlabelpos,
                    settings.animlabelcorner, settings.animlabelbg,
                    settings.animlabelsize)
        on(trigger) do _
            update_animlabel!(fd)
        end
    end
    on(ui_state.dim_obs) do _
        refresh_anim_values!(fd)
    end
    update_animlabel!(fd)

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
        rebuild_overlay!(fd)
        refresh_anim_values!(fd)
        apply_kwargs!(fd, ui_state.kwargs[])
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
    fd.anim_segments[] = compile_animlabel(
        fd.plot_data.dataset, ui_state.variable[], fd.plot_data.sel_dims[],
        ui_state.pdim[], fd.settings.animlabel[],
        fd.settings.animlabelnumfmt[], fd.settings.animlabeldateformat[],
        fd.settings.animlabelsize[])
    rebuild_animrow!(fd)
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
            fd.plot_data.dataset, pdim, idx, seg.template,
            fd.settings.animlabelnumfmt[], fd.settings.animlabeldateformat[])
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

"Rebuild the title-row segment labels (configuration-level change)."
function rebuild_animrow!(fd::FigureData)::Nothing
    gl = fd.animrow
    foreach(delete!, contents(gl))
    segments = fd.anim_segments[]
    if fd.settings.animlabelpos[] !== :title || isempty(segments)
        # never leave the layout contentless after trim! (zero rows), and
        # never use an empty-string Label (degenerate text extent): both
        # report NaN sizes that poison the whole figure solve
        Label(gl[1, 1], " "; fontsize = 1, visible = false)
        trim!(gl)
        colsize!(gl, 1, Auto())
        return nothing
    end
    slot = 0
    for (i, seg) in enumerate(segments)
        # The Label auto-sizes to its text and is aligned inside a column
        # of FIXED width. Fixing the Label's own width instead does NOT
        # align the text: Label halign places the block in its cell, so a
        # block as wide as the cell leaves the text at its left edge --
        # and the unit after a growing value visibly crawls.
        if seg.dynamic
            slot += 1
            ensure_slots!(fd, slot)
            Label(gl[1, i], fd.anim_slots[slot];
                  fontsize = fd.settings.animlabelsize[],
                  halign = :right, tellwidth = false)
        else
            Label(gl[1, i], seg.text;
                  fontsize = fd.settings.animlabelsize[],
                  halign = :left, tellwidth = false)
        end
        colsize!(gl, i, Fixed(seg.width))
    end
    colgap!(gl, 0)
    trim!(gl)
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
        fd.cbar[] = Colorbar(fd.fig[2, 2], fd.plot_obj[],
            width = 30, tellwidth = false, tellheight = false)
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
    :title => FigureSettingsHandler(
        :title, Union{Nothing, AbstractString}, set_title!),
    :titlesize => FigureSettingsHandler(:titlesize, Real, set_titlesize!),
    :animlabelsize => FigureSettingsHandler(
        :animlabelsize, Real, set_animlabelsize!),
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
            :animlabelnumfmt => Constants.NUMBER_FORMAT,
            :animlabeldateformat => Constants.DATETIME_FORMAT,
            :animlabelcorner => Constants.ANIMLABEL_CORNER,
            :animlabelbg => Constants.ANIMLABEL_BACKGROUND,
            :title => nothing,
            :titlesize => Float64(Constants.TITLESIZE),
            :animlabelsize => Float64(Constants.LABELSIZE),
        )
        return haskey(defaults, property) ? defaults[property] : :delete
    elseif isa(target_object, Makie.AbstractAxis)
        defaults = Dict(
            :xlabel => fd.plot_data.labels.xlabel[],
            :ylabel => fd.plot_data.labels.ylabel[],
            :zlabel => fd.plot_data.labels.zlabel[],
        )
        return haskey(defaults, property) ? defaults[property] : :delete
    end
    
    :delete
end
    

function get_property_mappings(kwargs::OrderedDict{Symbol, Any}, fig_data::FigureData)::Vector{PropertyMapping}
    mappings = Vector{PropertyMapping}()
    for (property, intended_value) in kwargs
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


function create_regular_2d_axis(fd::FigureData)::Axis
    aspect = Observable{Any}(compute_aspect2d(fd, fd.plot_data.x[], fd.plot_data.y[]))
    for trigger in (fd.plot_data.x, fd.plot_data.y)
        on(trigger) do _
            aspect[] = compute_aspect2d(fd, fd.plot_data.x[], fd.plot_data.y[])
        end
    end

    ax = Axis(
        fd.fig[2, 1],
        xlabel = fd.plot_data.labels.xlabel,
        ylabel = fd.plot_data.plot_type[].ndims > 1 ? fd.plot_data.labels.ylabel : "",
        aspect = aspect,
        limits = compute_2d_limits(fd),
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
        ax_layout,
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.labels.ylabel,
        zlabel = plot_data.plot_type[].ndims > 2 ? plot_data.labels.zlabel : "",
        aspect = @lift(compute_aspect3d(
            fd, $(fd.plot_data.x), $(fd.plot_data.y), $(fd.plot_data.z))
        ),
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