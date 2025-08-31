module Plotting

using DataStructures: OrderedDict
using Makie
using GLMakie

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
        (ax, x, y, z, d) -> volume!(ax, (x[1], x[end]), (y[1], y[end]), (z[1], z[end]), d, colormap = :balance)),
    Plot("contour3d", 3, 3, false,
        (ax, x, y, z, d) -> contour!(ax, (x[1], x[end]), (y[1], y[end]), (z[1], z[end]), d, colormap = :balance)),
])

const PLOT_OPTIONS_3D = collect(keys(PLOT_TYPES))
const PLOT_OPTIONS_2D = filter(k -> PLOT_TYPES[k].ndims <= 2, PLOT_OPTIONS_3D)
const PLOT_OPTIONS_1D = filter(k -> PLOT_TYPES[k].ndims == 1, PLOT_OPTIONS_3D)

# ============================================================
#  Plot types and their properties
# ============================================================
struct PlotData
    plot_type::Observable{Plot}
    x::Observable{Union{Array, Nothing}}
    y::Observable{Union{Array, Nothing}}
    z::Observable{Union{Array, Nothing}}
    d::Vector{Observable{Union{Array, Nothing}}}
end

function init_data_arrays()
    # TODO
    [Observable(nothing) for _ in 1:3] # max 3D data
end

function init_plot_data(
    plot_menu::UI.PlotMenu,
    ui_state::UI.State,
    dataset::Data.CDFDataset,
)
    plot_type = @lift(PLOT_TYPES[$(plot_menu.plot_type.selection)])
    x = Data.get_dim_array(dataset, ui_state.x_name)
    y = Data.get_dim_array(dataset, ui_state.y_name)
    z = Data.get_dim_array(dataset, ui_state.z_name)
    d = init_data_arrays()
    PlotData(plot_type, x, y, z, d)
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
    title = @lift(get_label($(ui_state.variable)))
    xlabel = @lift(get_label($(ui_state.x_name)))
    ylabel = @lift(get_label($(ui_state.y_name)))
    zlabel = @lift(get_label($(ui_state.z_name)))
    FigureLabels(title, xlabel, ylabel, zlabel)
end

# ============================================================
#  Figure data structure
# ============================================================

struct FigureData
    fig::Figure
    ax::Observable{Union{Makie.AbstractAxis, Nothing}}
    plotobj::Observable{Union{Makie.AbstractPlot, Nothing}}
    cbar::Observable{Union{Colorbar, Nothing}}
    labels::FigureLabels
end

function create_figure()
    GLMakie.activate!()
    fig = Figure(size = (1200, 800))
    theme = merge(theme_minimal(), theme_latexfonts())
    set_theme!(theme)
    fig
end

function create_2d_axis(
    labels::FigureLabels,
    plot_type::Plot,
    ax_layout::GridLayout,
)
    Axis(
        ax_layout,
        xlabel = labels.xlabel,
        ylabel = plot_type.ndims > 1 ? labels.ylabel : "",
        xlabelsize = 20,    
        ylabelsize = 20,    
        title = labels.title,
        titlesize = 24,
    )
end

function create_3d_axis(
    labels::FigureLabels,
    plot_type::Plot,
    ax_layout::GridLayout,
)
    Axis3(
        ax_layout,
        xlabel = labels.xlabel,
        ylabel = labels.ylabel,
        zlabel = plot_type.ndims > 2 ? labels.zlabel : "",
        xlabelsize = 20,    
        ylabelsize = 20,
        zlabelsize = 20,
        title = labels.title,
        titlesize = 24,
    )
end

function create_axis(
    labels::FigureLabels,
    plot_type::Observable{Plot},
    ax_layout::GridLayout,
)
    ax = Observable{Union{Makie.AbstractAxis, Nothing}}(nothing)

    on(plot_type) do pt
        ax[] !== nothing && delete!(ax[])
        if pt.ax_ndims == 2
            ax[] = create_2d_axis(labels, pt, ax_layout)
        elseif pt.ax_ndims == 3
            ax[] = create_3d_axis(labels, pt, ax_layout)
        else
            ax[] = nothing
        end
    end
    ax
end

function create_plot_object(
    cbar_layout::GridLayout,
    plot_type::Observable{Plot},
    ax::Observable{Union{Makie.AbstractAxis, Nothing}},
    plot_data::PlotData,
)
    plot_obj = Observable{Union{Makie.AbstractPlot, Nothing}}(nothing)
    cbar = Observable{Union{Colorbar, Nothing}}(nothing)

    on(ax) do a
        # first we clear the previous plot
        plot_obj[] !== nothing && delete!(plot_obj[])
        cbar[] !== nothing && delete!(cbar[])
        plot_type[].type == "Info" && return  # TODO

        # then we create the new plot
        plot_obj[] = plot_type[].func(
            a, plot_data.x, plot_data.y, plot_data.z, plot_data.d[1])
        # and add a colorbar if needed
        if plot_type[].colorbar
            cbar[] = Colorbar(cbar_layout, plot_obj[],
                width = 30, tellwidth = false, tellheight = false)
        end

        # TODO
        # notify(plot_settings.stored_string)
        # notify(axes_settings.stored_string)
        # update_coord_sliders!()
    end

    (plot_obj, cbar)
end

function init_figure_data(
    ui_state::UI.State,
    dataset::Data.CDFDataset,
    plot_type::Observable{Plot},
)
    fig = create_figure()
    labels = init_figure_labels(ui_state, dataset)
    ax = create_axis(labels, plot_type, fig[1, 2])
    plotobj, cbar = create_plot_object(fig[1, 3], plot_type, ax, plot_data)
    FigureData(fig, ax, plotobj, cbar, labels)
end

end # module Plotting