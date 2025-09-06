using Test
using GLMakie
using CDFViewer.Constants
using CDFViewer.Plotting

function create_dummy_data(number_of_dims)
    x = collect(1:5)
    y = number_of_dims >= 2 ? collect(1:6) : nothing
    z = number_of_dims == 3 ? collect(1:7) : nothing
    d = if number_of_dims == 1
        rand(length(x))
    elseif number_of_dims == 2
        rand(length(x), length(y))
    elseif number_of_dims == 3
        rand(length(x), length(y), length(z))
    else
        nothing
    end
    (Observable(x), Observable(y), Observable(z), Observable(d))
end

@testset "Plot Types" begin

    # Test the plot options
    number_of_plots = length(keys(Plotting.PLOT_TYPES))
    @test length(Plotting.get_plot_options(3)) == number_of_plots
    @test length(Plotting.get_plot_options(2)) < number_of_plots
    @test length(Plotting.get_plot_options(1)) < length(Plotting.get_plot_options(2))

    # Test the plot struct
    for (name, plot) in Plotting.PLOT_TYPES
        @test plot isa Plotting.Plot
        @test plot.type == name
        @test plot.ndims in (0, 1, 2, 3)
        @test plot.func isa Function
        @test plot.make_axis isa Function
    end

    # Test the get_plot_options function
    @test "volume" ∈ Plotting.get_plot_options(4)
    @test "volume" ∈ Plotting.get_plot_options(3)
    @test "heatmap" ∈ Plotting.get_plot_options(2)
    @test "volume" ∉ Plotting.get_plot_options(2)
    @test "line" ∈ Plotting.get_plot_options(1)
    @test "heatmap" ∉ Plotting.get_plot_options(1)
    @test "Info" ∈ Plotting.get_plot_options(0)

    # Test the fallback function
    @test Plotting.get_fallback_plot(4) == Constants.PLOT_DEFAULT_2D
    @test Plotting.get_fallback_plot(3) == Constants.PLOT_DEFAULT_2D
    @test Plotting.get_fallback_plot(2) == Constants.PLOT_DEFAULT_2D
    @test Plotting.get_fallback_plot(1) == Constants.PLOT_DEFAULT_1D
    @test Plotting.get_fallback_plot(0) == Constants.PLOT_INFO

    # Test the dimension plot function
    @test Plotting.get_dimension_plot(4) == Constants.PLOT_DEFAULT_3D
    @test Plotting.get_dimension_plot(3) == Constants.PLOT_DEFAULT_3D
    @test Plotting.get_dimension_plot(2) == Constants.PLOT_DEFAULT_2D
    @test Plotting.get_dimension_plot(1) == Constants.PLOT_DEFAULT_1D
    @test Plotting.get_dimension_plot(0) == Constants.PLOT_INFO

    # Test the plotting functions with dummy data
    fig = Figure()
    dataset = make_temp_dataset()
    ui = UI.init_ui_elements!(fig, dataset)
    plot_data = Plotting.init_plot_data(ui.state, dataset)

    for (name, plot) in Plotting.PLOT_TYPES
        empty!(fig)
        (x, y, z, d) = create_dummy_data(plot.ndims)
        ax = plot.make_axis(fig[1, 1], plot_data)
        plot.func(ax, x, y, z, d)
        plot.type === "Info" && continue  # Skip the Info plot as it does nothing
        @test !isempty(fig.content)  # Ensure something was plotted
    end

end

@testset "Figure Labels" begin

    dataset = make_temp_dataset()
    fig, ui = make_ui(dataset)

    labels = Plotting.init_figure_labels(ui.state, dataset)

    @test labels.title[] == "1d_float"
    @test labels.xlabel[] == "Not Selected"
    @test labels.ylabel[] == "Not Selected"
    @test labels.zlabel[] == "Not Selected"

    ui.state.variable[] = "both_atts_var"
    @test labels.title[] == "Both [m/s]"

    ui.state.x_name[] = "only_unit"
    @test labels.xlabel[] == "only_unit [n/a]"

    ui.state.y_name[] = "untaken"
    @test labels.ylabel[] == "untaken"
end


@testset "Plot Data" begin

    dataset = make_temp_dataset()
    fig, ui = make_ui(dataset)

    plot_data = Plotting.init_plot_data(ui.state, dataset)

    # Test types
    @test plot_data isa Plotting.PlotData
    @test plot_data.plot_type isa Observable{Plotting.Plot}
    @test plot_data.sel_dims isa Observable{Vector{String}}
    @test plot_data.x isa Observable
    @test plot_data.y isa Observable
    @test plot_data.z isa Observable
    @test plot_data.d isa Vector
    @test plot_data.labels isa Plotting.FigureLabels

    # Test initial values
    @test plot_data.plot_type[] == Plotting.PLOT_TYPES["Info"]
    @test plot_data.sel_dims[] == String[]
    @test plot_data.x[] == collect(Float64, 1:1)
    @test plot_data.y[] == collect(Float64, 1:1)
    @test plot_data.z[] == collect(Float64, 1:1)
    for i in 1:3
        @test plot_data.d[i] isa Observable
        @test plot_data.d[i][] === nothing
    end

    #  Test updates

    # set the variable to something with many dimensions
    ui.state.variable[] = "5d_float"

    # Test the dimensions
    ui.state.x_name[] = "lon"
    ui.state.y_name[] = "lat"
    @test length(plot_data.x[]) == 5
    @test length(plot_data.y[]) == 7
    ui.state.y_name[] = "Not Selected"
    @test plot_data.y[] == collect(Float64, 1:1)
    plot_data.sel_dims

    # Test with 1d data
    ui.state.plot_type_name[] = "line"
    @test plot_data.plot_type[] == Plotting.PLOT_TYPES["line"]
    @test plot_data.sel_dims[] == ["lon"]
    @test plot_data.d[1][].size == (5,)

    # Test with 2d data
    ui.state.y_name[] = "lat"
    ui.state.plot_type_name[] = "heatmap"
    @test plot_data.plot_type[] == Plotting.PLOT_TYPES["heatmap"]
    @test plot_data.sel_dims[] == ["lon", "lat"]
    @test plot_data.d[2][].size == (5, 7)

    # Test changing the dimension
    ui.state.x_name[] = "only_unit"
    @test plot_data.sel_dims[] == ["only_unit", "lat"]
    @test plot_data.d[2][].size == (3, 7)
    ui.state.x_name[] = "lon"

    # Test with 3d data
    ui.state.z_name[] = "only_long"
    ui.state.plot_type_name[] = "volume"
    @test plot_data.plot_type[] == Plotting.PLOT_TYPES["volume"]
    @test plot_data.sel_dims[] == ["lon", "lat", "only_long"]
    @test plot_data.d[3][].size == (5, 7, 4)

    # Test the update switch
    plot_data.update_data_switch[] = false
    x_ori = plot_data.x[]
    d_ori = plot_data.d[1][]
    ui.state.x_name[] = "lat"
    @test plot_data.x[] == x_ori
    ui.state.variable[] = "2d_float"
    @test plot_data.d[1][] == d_ori
    ui.state.plot_type_name[] = "line"
    plot_data.update_data_switch[] = true
    @test length(plot_data.x[]) == 7
    @test plot_data.d[1][].size == (7,)

end

@testset "Figure Data" begin

    dataset = make_temp_dataset()
    fig, ui = make_ui(dataset)

    plot_data = Plotting.init_plot_data(ui.state, dataset)
    fig_data = Plotting.init_figure_data(fig, plot_data, ui.state)

    # Test types
    @test fig_data isa Plotting.FigureData
    @test fig_data.fig isa Figure
    @test fig_data.plot_data isa Plotting.PlotData
    @test fig_data.ax isa Observable{Union{Makie.AbstractAxis, Nothing}}
    @test fig_data.plot_obj isa Observable{Union{Makie.AbstractPlot, Nothing}}
    @test fig_data.cbar isa Observable{Union{Colorbar, Nothing}}

    # Test a 1D plot
    ui.state.variable[] = "5d_float"
    ui.state.x_name[] = "lon"
    ui.state.plot_type_name[] = "line"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.ax[] isa Axis
    @test fig_data.ax[].xlabel[] == "lon"
    @test fig_data.ax[].ylabel[] == ""
    @test fig_data.ax[].title[] == "5d_float"
    @test fig_data.plot_obj[] isa Lines
    @test fig_data.cbar[] === nothing
    ui.state.x_name[] = "only_unit"
    @test fig_data.ax[].xlabel[] == "only_unit [n/a]"
    ui.state.x_name[] = "lon"
    ui.state.variable[] = "both_atts_var"
    @test fig_data.ax[].title[] == "Both [m/s]"

    # Test a 2D plot
    ui.state.y_name[] = "lat"
    ui.state.variable[] = "5d_float"
    ui.state.plot_type_name[] = "heatmap"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.ax[] isa Axis
    @test fig_data.ax[].xlabel[] == "lon"
    @test fig_data.ax[].ylabel[] == "lat"
    @test fig_data.ax[].title[] == "5d_float"
    @test fig_data.plot_obj[] isa Heatmap
    @test fig_data.cbar[] isa Colorbar
    ui.state.x_name[] = "only_unit"
    @test fig_data.ax[].xlabel[] == "only_unit [n/a]"
    ui.state.y_name[] = "float_dim"
    @test fig_data.ax[].ylabel[] == "float_dim"
    ui.state.x_name[] = "lon"
    ui.state.variable[] = "2d_gap"
    @test fig_data.ax[].title[] == "2d_gap"

    # Test a 2D plot with 3D axis
    ui.state.plot_type_name[] = "surface"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.ax[] isa Axis3
    @test fig_data.ax[].xlabel[] == "lon"
    @test fig_data.ax[].ylabel[] == "float_dim"
    @test fig_data.ax[].zlabel[] == ""
    @test fig_data.ax[].title[] == "2d_gap"
    ui.state.plot_type_name[] = "wireframe"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.cbar[] === nothing

    # Test a 3D plot
    ui.state.variable[] = "5d_float"
    ui.state.x_name[] = "lon"
    ui.state.y_name[] = "lat"
    ui.state.z_name[] = "only_long"
    ui.state.plot_type_name[] = "volume"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.ax[] isa Axis3
    @test fig_data.ax[].xlabel[] == "lon"
    @test fig_data.ax[].ylabel[] == "lat"
    @test fig_data.ax[].zlabel[] == "Long"
    @test fig_data.ax[].title[] == "5d_float"
    @test fig_data.plot_obj[] isa Volume
    @test fig_data.cbar[] isa Colorbar
    ui.state.x_name[] = "float_dim"

    # Test the kwargs
    ui.state.plot_kw[] = "colorrange = (0.2, 0.8), colormap=:ice"
    @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
    fig_data.plot_obj[].colormap.parent.value == :ice

    ui.state.axes_kw[] = "titlevisible = false"
    @test fig_data.ax[].titlevisible[] == false

    # go back to a 2D plot and check that the settings still apply
    ui.state.plot_type_name[] = "heatmap"
    Plotting.create_axis!(fig_data, ui.state)
    @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
    fig_data.plot_obj[].colormap.parent.value == :ice
    @test fig_data.ax[].titlevisible[] == false

end