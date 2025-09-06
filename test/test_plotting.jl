using Test
using GLMakie
using CDFViewer.Constants
using CDFViewer.Plotting

@testset "Plotting.jl" begin

    # ============================================
    #  Plot Struct
    # ============================================

    @testset "Plot Struct" begin

        @testset "Number of Plot Options" begin
            number_of_plots = length(keys(Plotting.PLOT_TYPES))
            @test length(Plotting.get_plot_options(3)) == number_of_plots
            @test length(Plotting.get_plot_options(2)) < number_of_plots
            @test length(Plotting.get_plot_options(1)) < length(Plotting.get_plot_options(2))
        end

        @testset "Plot Struct Fields" begin
            for (name, plot) in Plotting.PLOT_TYPES
                @test plot isa Plotting.Plot
                @test plot.type == name
                @test plot.ndims in (0, 1, 2, 3)
                @test plot.func isa Function
                @test plot.make_axis isa Function
            end
        end

        @testset "Plot Options Functions" begin
            @test "volume" ∈ Plotting.get_plot_options(4)
            @test "volume" ∈ Plotting.get_plot_options(3)
            @test "heatmap" ∈ Plotting.get_plot_options(2)
            @test "volume" ∉ Plotting.get_plot_options(2)
            @test "line" ∈ Plotting.get_plot_options(1)
            @test "heatmap" ∉ Plotting.get_plot_options(1)
            @test "Info" ∈ Plotting.get_plot_options(0)
        end

        @testset "Fallback Plot Function" begin
            @test Plotting.get_fallback_plot(4) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(3) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_fallback_plot(0) == Constants.PLOT_INFO
        end

        @testset "Dimension Plot Function" begin
            @test Plotting.get_dimension_plot(4) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(3) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_dimension_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_dimension_plot(0) == Constants.PLOT_INFO
        end

        @testset "Plot Functions" begin
            # Arrange - helper functions
            function create_dummy_data(number_of_dims)
                x = collect(1:5)
                y = number_of_dims >= 2 ? collect(1:6) : nothing
                z = number_of_dims == 3 ? collect(1:7) : nothing
                d = number_of_dims == 1 ? rand(length(x)) :
                    number_of_dims == 2 ? rand(length(x), length(y)) :
                    number_of_dims == 3 ? rand(length(x), length(y), length(z)) :
                    nothing
                (Observable(x), Observable(y), Observable(z), Observable(d))
            end

            # Arrange - create a temporary figure and dataset
            fig = Figure()
            dataset = make_temp_dataset()
            ui = UI.init_ui_elements!(fig, dataset)
            plot_data = Plotting.init_plot_data(ui.state, dataset)

            for (name, plot) in Plotting.PLOT_TYPES
                # Act
                empty!(fig)
                (x, y, z, d) = create_dummy_data(plot.ndims)
                ax = plot.make_axis(fig[1, 1], plot_data)
                plotobj = plot.func(ax, x, y, z, d)

                # Assert
                plot.type === "Info" && continue  # Skip the Info plot as it does nothing
                @test !isempty(fig.content)  # Ensure something was plotted
                @test plotobj isa Makie.AbstractPlot
            end
        end
    end

    # ============================================
    #  Figure Labels
    # ============================================

    @testset "Figure Labels" begin

        # Arrange - helper function
        function init_figure_labels()
            dataset = make_temp_dataset()
            fig, ui = make_ui(dataset)
            labels = Plotting.init_figure_labels(ui.state, dataset)
            (labels, ui.state)
        end

        @testset "Default Labels" begin
            # Arrange
            (labels, state) = init_figure_labels()

            # Assert
            @test labels.title[] == "1d_float"
            @test labels.xlabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.ylabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.zlabel[] == Constants.NOT_SELECTED_LABEL
        end

        @testset "Updated Labels" begin
            # Arrange
            (labels, state) = init_figure_labels()

            # Act: change variable to something with long_name and units
            state.variable[] = "both_atts_var"
            # Assert
            @test labels.title[] == "Both [m/s]"

            # Act: change x to something with only units
            state.x_name[] = "only_unit"
            # Assert
            @test labels.xlabel[] == "only_unit [n/a]"

            # Act: change y to something with only long_name            
            state.y_name[] = "untaken"
            # Assert
            @test labels.ylabel[] == "untaken"
        end
    end

    # ============================================
    #  Plot Data
    # ============================================

    @testset "Plot Data" begin
        # Arrange - helper function
        function init_plot_data()
            dataset = make_temp_dataset()
            _fig, ui = make_ui(dataset)

            plot_data = Plotting.init_plot_data(ui.state, dataset)
            (plot_data, ui.state)
        end

        @testset "Types" begin
            # Arrange
            (plot_data, state) = init_plot_data()

            # Assert
            @test plot_data isa Plotting.PlotData
            @test plot_data.plot_type isa Observable{Plotting.Plot}
            @test plot_data.sel_dims isa Observable{Vector{String}}
            @test plot_data.x isa Observable
            @test plot_data.y isa Observable
            @test plot_data.z isa Observable
            @test plot_data.d isa Vector
            @test plot_data.labels isa Plotting.FigureLabels
        end

        @testset "Initial Values" begin
            # Arrange
            (plot_data, state) = init_plot_data()

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["Info"]
            @test plot_data.sel_dims[] == String[]
            @test plot_data.x[] == collect(Float64, 1:1)
            @test plot_data.y[] == collect(Float64, 1:1)
            @test plot_data.z[] == collect(Float64, 1:1)
            for i in 1:3
                @test plot_data.d[i] isa Observable
                @test plot_data.d[i][] === nothing
            end
        end

        @testset "Selected Dimensions" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"

            # Act: select x and y dimensions
            state.x_name[] = "lon"
            state.y_name[] = "lat"

            # Assert
            @test length(plot_data.x[]) == 5
            @test length(plot_data.y[]) == 7
            @test length(plot_data.z[]) == 1

            # Act: deselect y dimension
            state.y_name[] = Constants.NOT_SELECTED_LABEL

            # Assert
            @test length(plot_data.x[]) == 5
            @test length(plot_data.y[]) == 1
            @test length(plot_data.z[]) == 1
        end

        @testset "Data Arrays 1D" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.plot_type_name[] = "line"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["line"]
            @test plot_data.sel_dims[] == ["lon"]
            @test plot_data.d[1][].size == (5,)
            @test plot_data.d[2][] === nothing
            @test plot_data.d[3][] === nothing
        end

        @testset "Data Arrays 2D" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["heatmap"]
            @test plot_data.sel_dims[] == ["lon", "lat"]
            @test plot_data.d[1][] === nothing
            @test plot_data.d[2][].size == (5, 7)
            @test plot_data.d[3][] === nothing
        end
            
        @testset "Data Arrays 3D" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["volume"]
            @test plot_data.sel_dims[] == ["lon", "lat", "only_long"]
            @test plot_data.d[1][] === nothing
            @test plot_data.d[2][] === nothing
            @test plot_data.d[3][].size == (5, 7, 4)
        end

        @testset "Data at Dimension Change" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act
            state.x_name[] = "only_unit"

            # Assert
            @test plot_data.sel_dims[] == ["only_unit", "lat"]
            @test plot_data.d[2][].size == (3, 7)
        end

        @testset "Data Update Switch" begin
            # Arrange
            (plot_data, state) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act: disable updates
            plot_data.update_data_switch[] = false
            x_ori = plot_data.x[]
            d_ori = plot_data.d[1][]
            state.x_name[] = "lat"  # change x dimension
            state.variable[] = "2d_float"  # change variable
            state.plot_type_name[] = "line"  # change plot type

            # Assert: data should not have changed
            @test plot_data.x[] == x_ori
            @test plot_data.d[1][] == d_ori

            # Act: enable updates
            plot_data.update_data_switch[] = true

            # Assert: data should now reflect the changes
            @test length(plot_data.x[]) == 7
            @test plot_data.d[1][].size == (7,)
        end

    end

    # ============================================
    #  Figure Data
    # ============================================

    @testset "Figure Data" begin

        # Arrange - helper function
        function init_figure_data()
            dataset = make_temp_dataset()
            fig, ui = make_ui(dataset)

            plot_data = Plotting.init_plot_data(ui.state, dataset)
            fig_data = Plotting.init_figure_data(fig, plot_data, ui.state)
            (fig_data, ui.state)
        end

        @testset "Types" begin
            # Arrange
            (fig_data, state) = init_figure_data()

            # Assert
            @test fig_data isa Plotting.FigureData
            @test fig_data.fig isa Figure
            @test fig_data.plot_data isa Plotting.PlotData
            @test fig_data.ax isa Observable{Union{Makie.AbstractAxis, Nothing}}
            @test fig_data.plot_obj isa Observable{Union{Makie.AbstractPlot, Nothing}}
            @test fig_data.cbar isa Observable{Union{Colorbar, Nothing}}
        end

        @testset "Plot 1D" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lat"
            state.plot_type_name[] = "line"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test fig_data.ax[].xlabel[] == "lat"
            @test fig_data.ax[].ylabel[] == ""
            @test fig_data.ax[].title[] == "5d_float"
            @test fig_data.plot_obj[] isa Lines
            @test fig_data.cbar[] === nothing

            # Act - change observables
            state.x_name[] = "lon"
            state.variable[] = "both_atts_var"

            # Assert
            @test fig_data.ax[].title[] == "Both [m/s]"
            @test fig_data.ax[].xlabel[] == "lon"
        end

        @testset "Plot 2D" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "lat"
            @test fig_data.ax[].title[] == "5d_float"
            @test fig_data.plot_obj[] isa Heatmap
            @test fig_data.cbar[] isa Colorbar

            # Act - change observables
            state.x_name[] = "lon"
            state.y_name[] = "float_dim"
            state.variable[] = "2d_gap"

            # Assert
            @test fig_data.ax[].title[] == "2d_gap"
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "float_dim"
        end

        @testset "Plot 2D with 3D Axis" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "2d_gap"
            state.x_name[] = "lon"
            state.y_name[] = "float_dim"
            state.plot_type_name[] = "surface"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "float_dim"
            @test fig_data.ax[].zlabel[] == ""
            @test fig_data.ax[].title[] == "2d_gap"
            @test fig_data.plot_obj[] isa Surface
            @test fig_data.cbar[] isa Colorbar
        end

        @testset "Plot 3D" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "lat"
            @test fig_data.ax[].zlabel[] == "Long"
            @test fig_data.ax[].title[] == "5d_float"
            @test fig_data.plot_obj[] isa Volume
            @test fig_data.cbar[] isa Colorbar

            # Act - change observables
            state.x_name[] = "float_dim"

            # Assert
            @test fig_data.ax[].xlabel[] == "float_dim"
        end

        @testset "Change Plot Type" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)

            # Act - change to a 3D plot type
            state.plot_type_name[] = "surface"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.plot_obj[] isa Surface
            @test fig_data.cbar[] isa Colorbar
        end

        @testset "Change Plot Dimension" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)

            # Act - change to a 3D plot type
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.plot_obj[] isa Volume
            @test fig_data.cbar[] isa Colorbar

            # Act - change to a 1D plot type
            state.plot_type_name[] = "line"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test fig_data.plot_obj[] isa Lines
            @test fig_data.cbar[] === nothing
        end

        @testset "Apply Kwargs" begin
            # Arrange
            (fig_data, state) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)

            # Act - set some kwargs
            state.plot_kw[] = "colorrange = (0.2, 0.8), colormap=:ice"
            state.axes_kw[] = "titlevisible = false"

            # Assert
            @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
            @test fig_data.plot_obj[].colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false

            # Act - change to a 3D plot type
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"
            Plotting.create_axis!(fig_data, state)

            # Assert - the kwargs should still apply
            @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
            @test fig_data.plot_obj[].colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false
        end
    end
end