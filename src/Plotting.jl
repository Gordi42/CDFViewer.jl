module Plotting

using DataStructures: OrderedDict
using Makie
using GLMakie

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
    Plot(Constants.PLOT_INFO, 0, false,
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
        [Constants.PLOT_INFO]
    end
end

function get_fallback_plot(ndims::Int)::String
    if ndims >= 2
        Constants.PLOT_DEFAULT_2D
    elseif ndims == 1
        Constants.PLOT_DEFAULT_1D
    else
        Constants.PLOT_INFO
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
        Constants.PLOT_INFO
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
end

function FigureData(fig::Figure, plot_data::PlotData, ui_state::UI.State)::FigureData
    # Create axis, plot object, and colorbar observables
    ax = Observable{Union{Makie.AbstractAxis, Nothing}}(nothing)
    plot_obj = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    cbar = Observable{Union{Colorbar, Nothing}}(nothing)
    data_inspector = Observable{Union{DataInspector, Nothing}}(nothing)

    # Construct the FigureData
    fd = FigureData(fig, plot_data, ax, plot_obj, cbar, data_inspector)

    # Setup a listener to create the plot if the axis changes
    on(ax) do a
        a === nothing && return
        # first we clear the previous plot
        cbar[] !== nothing && delete!(cbar[])
        cbar[] = nothing
        plot_data.plot_type[].type == "Info" && return  # TODO

        # then we create the new plot
        plot_obj[] = plot_data.plot_type[].func(
            a, plot_data.x, plot_data.y, plot_data.z,
            plot_data.d[plot_data.plot_type[].ndims])
        # and add a colorbar if needed
        if plot_data.plot_type[].colorbar
            cbar[] = Colorbar(fig[1, 3], plot_obj[],
                width = 30, tellwidth = false, tellheight = false)
            colsize!(fig.layout, 3, Relative(0.05))
        end
        apply_kwargs!(fd, ui_state.plot_kw[])
    end

    # Setup listeners to apply axis and plot keyword arguments
    on(ui_state.plot_kw) do kw_str
        plot_obj[] !== nothing && apply_kwargs!(fd, kw_str)
    end
    
    # return the FigureData
    fd
end

function create_figure()::Figure
    GLMakie.activate!()
    fig = Figure(size = Constants.FIGSIZE)
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

    # set the column sizes
    colsize!(fig.layout, 1, Relative(0.3))   # Controls Panel should take 30% of width
    colgap!(fig.layout, 50)

    fig
end

function create_axis!(fig_data::FigureData, ui_state::UI.State)::Nothing
    fig_data.ax[] !== nothing && delete!(fig_data.ax[])
    fig_data.ax[] = fig_data.plot_data.plot_type[].make_axis(fig_data.fig[1, 2], fig_data.plot_data)
    if !isnothing(fig_data.ax[])
        apply_kwargs!(fig_data, ui_state.plot_kw[])
        if fig_data.data_inspector[] === nothing
            fig_data.data_inspector[] = DataInspector(fig_data.ax[])
        end
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

function apply_kwarg!(fig_data::FigureData, key::Symbol, value::Any)::Nothing
    for obj in (fig_data.ax[], fig_data.plot_obj[], fig_data.cbar[])
        key ∉ propertynames(obj) && continue
        try
            setproperty!(obj, key, value)
            return nothing
        catch _
            # try next object
        end
    end
    @warn "Failed to apply keyword argument: $key => $value"
    nothing
end

function apply_kwargs!(fig_data::FigureData, kw_str::Union{String, Nothing})::Nothing
    kw_str === nothing && return
    kwargs = Parsing.parse_kwargs(kw_str)
    for (key, value) in kwargs
        apply_kwarg!(fig_data, key, value)
    end
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
    Plot("contour3d", 3, false,
        (ax, x, y, z, d) -> contour!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance),
        create_3d_axis),
]
    PLOT_TYPES[plot.type] = plot
end


end