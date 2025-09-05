module Plotting

using DataStructures: OrderedDict
using Makie
using GLMakie

import ..Constants
import ..Data
import ..UI

# ============================================================
#  Plot types and their properties
# ============================================================

struct Plot
    type::String
    ndims::Int
    ax_ndims::Int
    colorbar::Bool
    func::Function
end

const PLOT_TYPES = OrderedDict(plot.type => plot for plot in [
    Plot("Info", 0, 0, false,
        (ax, x, y, z, d) -> nothing),
    Plot("heatmap", 2, 2, true,
        (ax, x, y, z, d) -> heatmap!(ax, x, y, d, colormap = :balance)),
    Plot("contour", 2, 2, false,
        (ax, x, y, z, d) -> contour!(ax, x, y, d, colormap = :balance)),
    Plot("contourf", 2, 2, true,
        (ax, x, y, z, d) -> contourf!(ax, x, y, d, colormap = :balance)),
    Plot("surface", 2, 3, true,
        (ax, x, y, z, d) -> surface!(ax, x, y, d, colormap = :balance)),
    Plot("wireframe", 2, 3, false,
        (ax, x, y, z, d) -> wireframe!(ax, x, y, d, color = :royalblue3)),
    Plot("line", 1, 2, false,
        (ax, x, y, z, d) -> lines!(ax, x, d, color = :royalblue3)),
    Plot("scatter", 1, 2, false,
        (ax, x, y, z, d) -> scatter!(ax, x, d, color = :royalblue3)),
    Plot("volume", 3, 3, true,
        (ax, x, y, z, d) -> volume!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance)),
    Plot("contour3d", 3, 3, false,
        (ax, x, y, z, d) -> contour!(
            ax, @lift(($x[1], $x[end])), @lift(($y[1], $y[end])), @lift(($z[1], $z[end])),
            d, colormap = :balance)),
])

const PLOT_OPTIONS_3D = collect(keys(PLOT_TYPES))
const PLOT_OPTIONS_2D = filter(k -> PLOT_TYPES[k].ndims ≤ 2, PLOT_OPTIONS_3D)
const PLOT_OPTIONS_1D = filter(k -> PLOT_TYPES[k].ndims ≤ 1, PLOT_OPTIONS_3D)

function get_plot_options(ndims::Int)
    if ndims >= 3
        PLOT_OPTIONS_3D
    elseif ndims == 2
        PLOT_OPTIONS_2D
    elseif ndims == 1
        PLOT_OPTIONS_1D
    else
        ["Info"]
    end
end

function get_fallback_plot(ndims::Int)
    if ndims >= 2
        "heatmap"
    elseif ndims == 1
        "line"
    else
        "Info"
    end
end

function get_dimension_plot(ndims::Int)
    if ndims >= 3
        "volume"
    elseif ndims == 2
        "heatmap"
    elseif ndims == 1
        "line"
    else
        "Info"
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

function init_figure_labels(ui_state::UI.State, dataset::Data.CDFDataset)
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

function construct_selected_dimensions(ui_state::UI.State, plot_type::Observable{Plot})
    @lift([
        $(ui_state.x_name),
        $(ui_state.y_name),
        $(ui_state.z_name),][1:$plot_type.ndims])
end

function init_data_arrays(
    ui_state::UI.State,
    sel_dims::Observable{Vector{String}},
    dataset::Data.CDFDataset,
    update_switch::Observable{Bool},
)
    data = [Observable{Union{Array, Nothing}}(nothing) for _ in 1:3] # max 3D data
    function updata_data!()
        !(update_switch[]) && return
        ndims = length(sel_dims[])
        ndims == 0 && return
        data[ndims][] = Data.get_data(
            dataset, ui_state.variable[], sel_dims[], ui_state.dim_obs[])
    end

    for trigger in (ui_state.variable, sel_dims, ui_state.dim_obs, update_switch)
        on(trigger) do _
            updata_data!()
        end
    end
    data
end

function init_plot_data(ui_state::UI.State, dataset::Data.CDFDataset)
    plot_type = @lift(PLOT_TYPES[$(ui_state.plot_type_name)])
    sel_dims = construct_selected_dimensions(ui_state, plot_type)
    update_switch = Observable(true)
    x = Data.get_dim_array(dataset, ui_state.x_name, update_switch)
    y = Data.get_dim_array(dataset, ui_state.y_name, update_switch)
    z = Data.get_dim_array(dataset, ui_state.z_name, update_switch)
    d = init_data_arrays(ui_state, sel_dims, dataset, update_switch)
    labels = init_figure_labels(ui_state, dataset)
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
end

function create_figure()
    GLMakie.activate!()
    fig = Figure(size = (1200, 800))
    theme = merge(theme_minimal(), theme_latexfonts())
    set_theme!(theme)
    fig
end

function create_2d_axis(ax_layout::GridPosition, plot_data::PlotData)
    Axis(
        ax_layout,
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.plot_type[].ndims > 1 ? plot_data.labels.ylabel : "",
        xlabelsize = 20,    
        ylabelsize = 20,    
        title = plot_data.labels.title,
        titlesize = 24,
    )
end

function create_3d_axis(ax_layout::GridPosition, plot_data::PlotData)
    Axis3(
        ax_layout,
        xlabel = plot_data.labels.xlabel,
        ylabel = plot_data.labels.ylabel,
        zlabel = plot_data.plot_type[].ndims > 2 ? plot_data.labels.zlabel : "",
        xlabelsize = 20,    
        ylabelsize = 20,
        zlabelsize = 20,
        title = plot_data.labels.title,
        titlesize = 24,
    )
end

function apply_kwargs!(obj::Union{Makie.AbstractAxis, Makie.AbstractPlot}, kw_str::Union{String, Nothing})
    kw_str === nothing && return
    kw = try
        kw_expr = Meta.parse("Dict(" * kw_str * ")")
        Dict(Symbol(pair.args[1]) => eval(pair.args[2]) for pair in kw_expr.args[2:end])
    catch e
        @warn "Failed to parse keyword arguments: $e"
    end
    for (key, value) in kw
        try
            setproperty!(obj, key, value)
        catch e
            @warn "Failed to set property $key to $value: $e"
        end
    end
end


function create_plot_object(
    cbar_layout::GridPosition,
    ax::Observable{Union{Makie.AbstractAxis, Nothing}},
    plot_data::PlotData,
    ui_state::UI.State,
)
    plot_obj = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    cbar = Observable{Union{Colorbar, Nothing}}(nothing)

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
            cbar[] = Colorbar(cbar_layout, plot_obj[],
                width = 30, tellwidth = false, tellheight = false)
        end
        apply_kwargs!(plot_obj[], ui_state.plot_kw[])
    end

    (plot_obj, cbar)
end

function init_figure_data(fig::Figure, plot_data::PlotData, ui_state::UI.State)
    ax = Observable{Union{Makie.AbstractAxis, Nothing}}(nothing)
    plot_obj, cbar = create_plot_object(fig[1, 3], ax, plot_data, ui_state)

    on(ui_state.axes_kw) do kw_str
        ax[] !== nothing && apply_kwargs!(ax[], kw_str)
    end

    on(ui_state.plot_kw) do kw_str
        plot_obj[] !== nothing && apply_kwargs!(plot_obj[], kw_str)
    end
    
    FigureData(fig, plot_data, ax, plot_obj, cbar)
end

function create_axis!(fig_data::FigureData, ui_state::UI.State)
    fig_data.ax[] !== nothing && delete!(fig_data.ax[])
    if fig_data.plot_data.plot_type[].ax_ndims == 2
        fig_data.ax[] = create_2d_axis(fig_data.fig[1, 2], fig_data.plot_data)
    elseif fig_data.plot_data.plot_type[].ax_ndims == 3
        fig_data.ax[] = create_3d_axis(fig_data.fig[1, 2], fig_data.plot_data)
    else
        fig_data.ax[] = nothing
    end
    fig_data.ax[] !== nothing && apply_kwargs!(fig_data.ax[], ui_state.axes_kw[])
end

function clear_axis!(fig_data::FigureData)
    if fig_data.cbar[] !== nothing
        delete!(fig_data.cbar[])
        fig_data.cbar[] = nothing
    end
    if fig_data.ax[] !== nothing
        delete!(fig_data.ax[])
        fig_data.ax[] = nothing
    end
    fig_data.plot_obj[] = nothing
end

end # module Plotting