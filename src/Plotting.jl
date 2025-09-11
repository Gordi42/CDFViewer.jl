module Plotting

using DataStructures: OrderedDict
using Makie
using GLMakie
using Suppressor

import ..Constants
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
        (layout, plot_data) -> nothing),
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
end

function PlotData(ui_state::UI.State, dataset::Data.CDFDataset)::PlotData
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
    PlotData(plot_type, sel_dims, x, y, z, d, update_switch, labels)
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
    data_inspector::Observable{Union{DataInspector, Nothing}}
    tasks::Observable{Vector{Task}}
    figsize::Observable{Tuple{Int, Int}}
end

function FigureData(plot_data::PlotData, ui_state::UI.State)::FigureData
    # Create axis, plot object, and colorbar observables
    figsize = Observable(Constants.FIGSIZE)
    fig = create_figure(figsize[])
    ax = Observable{Union{Makie.AbstractAxis, Nothing}}(nothing)
    plot_obj = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    cbar = Observable{Union{Colorbar, Nothing}}(nothing)
    data_inspector = Observable{Union{DataInspector, Nothing}}(nothing)

    # Construct the FigureData
    fd = FigureData(fig, plot_data, ax, plot_obj, cbar,
        data_inspector, Observable(Task[]), figsize)

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
        apply_kwargs!(fd, ui_state.plot_kw[])
    end

    # Setup listeners to apply axis and plot keyword arguments
    on(ui_state.plot_kw) do kw_str
        plot_obj[] !== nothing && apply_kwargs!(fd, kw_str)
    end
    
    # return the FigureData
    fd
end

function create_figure(figsize::Tuple{Int, Int})::Figure
    GLMakie.activate!()
    fig = Figure(size = figsize)
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
    )
    theme = merge(theme_latexfonts(), theme_minimal())
    theme = merge(theme, cust_theme)
    set_theme!(theme)

    fig
end

function create_axis!(fig_data::FigureData, ui_state::UI.State)::Nothing
    fig_data.ax[] !== nothing && delete!(fig_data.ax[])
    fig_data.ax[] = fig_data.plot_data.plot_type[].make_axis(fig_data.fig[1, 1], fig_data.plot_data)
    if !isnothing(fig_data.ax[])
        apply_kwargs!(fig_data, ui_state.plot_kw[])
        if fig_data.data_inspector[] === nothing
            fig_data.data_inspector[] = DataInspector(fig_data.ax[])
        end
    end
    nothing
end

function add_colorbar!(fig_data::FigureData)::Nothing
    if fig_data.cbar[] !== nothing
        delete!(fig_data.cbar[])
        fig_data.cbar[] = nothing
    end
    if fig_data.plot_data.plot_type[].colorbar && fig_data.plot_obj[] !== nothing
        fig_data.cbar[] = Colorbar(fig_data.fig[1, 2], fig_data.plot_obj[],
            width = 30, tellwidth = false, tellheight = false)
        colsize!(fig_data.fig.layout, 2, Relative(0.05))
    end
    nothing
end

function clear_axis!(fig_data::FigureData)::Nothing
    if fig_data.cbar[] !== nothing
        delete!(fig_data.cbar[])
        fig_data.cbar[] = nothing
    end
    if fig_data.ax[] !== nothing
        delete!(fig_data.ax[])
        fig_data.ax[] = nothing
    end
    fig_data.plot_obj[] = nothing
    nothing
end

function resize_figure!(fd::FigureData, new_size::Tuple{Int, Int})::Nothing
    try
        resize!(fd.fig, new_size[1], new_size[2])
        fd.figsize[] = new_size
    catch e
        @error "Error resizing figure: $e"
    end
    nothing
end

function set_colorbar!(fd::FigureData, show::Bool)::Nothing
    if show
        if !fd.plot_data.plot_type[].colorbar
            @warn "Current plot type does not support colorbar"
            return nothing
        end
        add_colorbar!(fd)
        return nothing
    end
    if fd.cbar[] !== nothing
        delete!(fd.cbar[])
        fd.cbar[] = nothing
    end
    nothing
end

function Base.setproperty!(fd::FigureData, property::Symbol, value::Any)::Nothing
    if property == :figsize
        # check that the value is a tuple of two integers
        if !isa(value, Tuple{Int, Int})
            @error "Figsize must be a tuple of two integers"
            return nothing
        end
        resize_figure!(fd, value)
    elseif property == :cbar
        if !isa(value, Bool)
            return nothing
        end
        set_colorbar!(fd, value)
    else
        @error "Property $property not recognized in FigureData"
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

function get_property_mappings(kwargs::Dict{Symbol, Any}, fig_data::FigureData)::Vector{PropertyMapping}
    mappings = Vector{PropertyMapping}()
    for (property, intended_value) in kwargs
        found_targets = 0
        for target_obj in (fig_data.ax[], fig_data.plot_obj[], fig_data.cbar[], fig_data)
            target_obj === nothing && continue
            property ∉ propertynames(target_obj) && continue
            
            # Get the current value of the property
            current_value = getproperty(target_obj, property)
            # If it's an Observable, get its value
            current_value = try
                current_value[]
            catch
                current_value  # not an observable
            end
            
            push!(mappings, PropertyMapping(property, target_obj, current_value, intended_value))
            found_targets += 1
        end
        found_targets == 0 && @warn "Property $property not found in any plot object"
    end
    return mappings
end

function apply_property_mappings!(mappings::Vector{PropertyMapping})::Nothing
    for mapping in mappings
        mapping.current_value == mapping.intended_value && continue
        try
            setproperty!(mapping.target_object, mapping.property, mapping.intended_value)
        catch e
            @warn("Error setting property $mapping.property to $mapping.intended_value: $e")
        end
    end
    nothing
end

function apply_original_property_mappings!(mappings::Vector{PropertyMapping})::Nothing
    for mapping in mappings
        try
            setproperty!(mapping.target_object, mapping.property, mapping.current_value)
        catch e
            @warn("Error setting property $mapping.property to $mapping.current_value: $e")
        end
    end
    nothing
end

function wait_for_n_cycles(fig::Figure, n::Int)::Nothing
    tick_count = 0
    on(fig.scene.events.tick) do tick
        tick_count += 1
    end
    while tick_count < n
        yield()
    end
    nothing
end

function apply_kwargs!(fig_data::FigureData, kw_str::Union{String, Nothing})::Nothing
    kw_str === nothing && return
    # Wait for all previous tasks to complete
    while !all(istaskdone, fig_data.tasks[])
        yield()
    end
    fig_data.tasks[] = Task[]

    kwargs = Parsing.parse_kwargs(kw_str)
    mappings = get_property_mappings(kwargs, fig_data)

    task = @async begin
        output = @capture_err begin
            # @warn "Applying keyword arguments: $kw_str"
            apply_property_mappings!(mappings)

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
            apply_original_property_mappings!(mappings)
        end
    end
    push!(fig_data.tasks[], task)
    nothing
end

# ============================================================
#  Fill up plot functions
# ============================================================
function compute_aspect(x::Array, y::Array, default::Float64)::Float64
    x_ext = maximum(x) - minimum(x)
    y_ext = maximum(y) - minimum(y)
    ratio = x_ext / y_ext
    isfinite(ratio) || return default
    if ratio > 20 || ratio < 0.05
        default
    else
        ratio
    end
end

function compute_aspect(x::Array, y::Array, z::Array,
        default::Tuple{Float64, Float64, Float64})::Tuple{Float64, Float64, Float64}
    exts = [maximum(xi) - minimum(xi) for xi in (x, y, z)]
    exts = [ext == 0 ? 1.0 : ext for ext in exts]
    ratio = [exts[1] / exts[2], exts[2] / exts[2], exts[3] / exts[2]]
    ratio = [r > 20 || r < 0.05 ? default[i] : r for (i, r) in enumerate(ratio)]
    Tuple(ratio)
end

function create_2d_axis(ax_layout::GridPosition, plot_data::PlotData)::Axis
    aspect = Observable{Any}(compute_aspect(plot_data.x[], plot_data.y[], 1.0))
    for dim in (plot_data.x, plot_data.y)
        on(dim) do _
            aspect[] = compute_aspect(plot_data.x[], plot_data.y[], 1.0)
        end
    end

    Axis(
        ax_layout,
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.plot_type[].ndims > 1 ? plot_data.labels.ylabel : "",
        aspect = plot_data.plot_type[].ndims == 2 ? aspect : nothing,
        title = plot_data.labels.title,
    )
end

function create_3d_axis(ax_layout::GridPosition, plot_data::PlotData)::Axis3
    function get_aspect()::Tuple{Float64, Float64, Float64}
        aspect = compute_aspect(
            plot_data.x[], plot_data.y[], plot_data.z[],
            (1.0, 1.0, 1.0))
        if plot_data.plot_type[].ndims == 2
            aspect = (aspect[1], aspect[2], 0.4)
        end
        aspect
    end

    ax = Axis3(
        ax_layout,
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.labels.ylabel,
        zlabel = plot_data.plot_type[].ndims > 2 ? plot_data.labels.zlabel : "",
        aspect = get_aspect(),
        title = plot_data.labels.title,
    )

    for dim in (plot_data.x, plot_data.y, plot_data.z)
        on(dim) do _
            setproperty!(ax, :aspect, get_aspect())
        end
    end
    ax
end


for plot in [
    # 2D plots
    Plot("heatmap", 2, true,
        (ax, x, y, z, d) -> heatmap!(ax, x, y, d, colormap = :balance),
        create_2d_axis),
    Plot("contour", 2, false,
        (ax, x, y, z, d) -> contour!(ax, x, y, d, colormap = :balance),
        create_2d_axis),
    Plot("contourf", 2, true,
        (ax, x, y, z, d) -> contourf!(ax, x, y, d, colormap = :balance),
        create_2d_axis),
    Plot("surface", 2, true,
        (ax, x, y, z, d) -> surface!(ax, x, y, d, colormap = :balance),
        create_3d_axis),
    Plot("wireframe", 2, false,
        (ax, x, y, z, d) -> wireframe!(ax, x, y, d, color = :royalblue3),
        create_3d_axis),

    # 1D plots
    Plot("line", 1, false,
        (ax, x, y, z, d) -> lines!(ax, x, d, color = :royalblue3),
        create_2d_axis),
    Plot("scatter", 1, false,
        (ax, x, y, z, d) -> scatter!(ax, x, d, color = :royalblue3),
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