using Test
using GLMakie
using CDFViewer.Plotting

"Helper: create dummy data for plotting"
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
        error("Unsupported number of dimensions")
    end
    (x, y, z, d)
end

@testset "Plotting" begin

    # Test the plot options
    number_of_plots = length(keys(Plotting.PLOT_TYPES))
    @test length(Plotting.PLOT_OPTIONS_3D) == number_of_plots
    @test length(Plotting.PLOT_OPTIONS_2D) < number_of_plots
    @test length(Plotting.PLOT_OPTIONS_1D) < length(Plotting.PLOT_OPTIONS_2D)

    # Test the plot struct
    for (name, plot) in Plotting.PLOT_TYPES
        @test plot isa Plotting.Plot
        @test plot.type == name
        @test plot.ndims in (1, 2, 3)
        @test plot.ax_ndims in (2, 3)
        @test plot.func isa Function
    end

    # Test the plotting functions with dummy data
    fig = Figure()
    for (name, plot) in Plotting.PLOT_TYPES
        empty!(fig)
        (x, y, z, d) = create_dummy_data(plot.ndims)
        ax = plot.ax_ndims == 3 ? Axis3(fig[1, 1]) : Axis(fig[1, 1])
        plot.func(ax, x, y, z, d)
        @test !isempty(fig.content)  # Ensure something was plotted
    end

end