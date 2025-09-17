using Test
using DataStructures
using GLMakie
using CDFViewer.Constants
using CDFViewer.Plotting

@testset "Plotting.jl" begin

    # Arrange - helper function
    function init_figure_data()
        dataset = make_temp_dataset()
        ui = UI.UIElements(dataset)

        plot_data = Plotting.PlotData(ui.state, dataset)
        fig_data = Plotting.FigureData(plot_data, ui)
        (fig_data, ui.state, dataset)
    end

    function arrange_and_create_axis(var::String, sel::Vector{String}, plot_type::String)
        (fig_data, state, dataset) = init_figure_data()
        state.variable[] = var
        for (dim, name) in zip((state.x_name, state.y_name, state.z_name),
                (sel..., Constants.NOT_SELECTED_LABEL, Constants.NOT_SELECTED_LABEL))
            dim[] = name
        end
        state.plot_type_name[] = plot_type
        Plotting.create_axis!(fig_data, state)
        (fig_data, state, dataset)
    end

    function cleanup(dataset)
        GLMakie.closeall()
        close(dataset.ds)
    end

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
            @test Constants.NOT_SELECTED_LABEL ∈ Plotting.get_plot_options(0)
        end

        @testset "Fallback Plot Function" begin
            @test Plotting.get_fallback_plot(4) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(3) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_fallback_plot(0) == Constants.NOT_SELECTED_LABEL
        end

        @testset "Dimension Plot Function" begin
            @test Plotting.get_dimension_plot(4) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(3) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_dimension_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_dimension_plot(0) == Constants.NOT_SELECTED_LABEL
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
            dataset = make_temp_dataset()
            ui = UI.UIElements(dataset)
            fig = Figure()
            plot_data = Plotting.PlotData(ui.state, dataset)

            for (name, plot) in Plotting.PLOT_TYPES
                # Act
                empty!(fig)
                (x, y, z, d) = create_dummy_data(plot.ndims)
                ax = plot.make_axis(fig[1, 1], plot_data)
                plotobj = plot.func(ax, x, y, z, d)

                # Assert
                plot.type === Constants.NOT_SELECTED_LABEL && continue  # Skip the Info plot as it does nothing
                @test !isempty(fig.content)  # Ensure something was plotted
                @test plotobj isa Makie.AbstractPlot
            end

            # Cleanup
            GLMakie.closeall()
        end

        @testset "Compute Aspect Ratio" begin
            @testset "2D Aspect Ratio" begin
                default = 1234.0
                function assert_aspect_2d(x, y, expected; atol = 0.01)
                    aspect = Plotting.compute_aspect(x, y, default)
                    @test aspect ≈ expected atol=atol
                end

                assert_aspect_2d(collect(1:5), collect(1:5), 1.0)
                assert_aspect_2d(collect(1:5), collect(1:0.2:3.2), 4/2.2)
                assert_aspect_2d(rand(1000), rand(1000), 1.0, atol=0.1)  # should fail 1 in ~10^500 times
                assert_aspect_2d([0.2, -0.1, 0.4], [3.1, 0.1, 0.7], 0.5/3.0)
                assert_aspect_2d([0.1, 100.0, 32], [0.2, 0.3, 0.4], default)
                assert_aspect_2d([0.1, 0.2, 0.3], [0.1, 100.0, 32], default)
            end

            @testset "3D Aspect Ratio" begin
                default = 1234.0
                function assert_aspect_3d(x, y, z, expected; atol = 0.01)
                    aspect = Plotting.compute_aspect(x, y, z, (default, default, default))
                    for (a, b) in zip(aspect, expected)
                        @test a ≈ b atol=atol
                    end
                end

                assert_aspect_3d(collect(1:5), collect(1:5), collect(1:5), (1.0, 1.0, 1.0))
                assert_aspect_3d(collect(1:4), collect(1:5), collect(1:6), (3/4, 1.0, 5/4))
                assert_aspect_3d(collect(1:5), collect(1:0.2:3.2), collect(1:0.1:4.1), (4/2.2, 2.2/2.2, 3.1/2.2))
                assert_aspect_3d(rand(1000), rand(1000), rand(1000), (1.0, 1.0, 1.0), atol=0.1)
                assert_aspect_3d([0.2, -0.1, 0.4], [3.1, 0.1, 0.7], [0.5, 0.6, -0.2], (0.5/3.0, 3.0/3.0, 0.8/3.0))
                assert_aspect_3d([0.1, 100.0, 32], [0.2, 0.3, 0.4], [0.5, 0.6, -0.2], (default, 1.0, 0.8/0.2))
                assert_aspect_3d([0.1, 0.2, 0.3], [0.1, 100.0, 32], [0.5, 0.6, -0.2], (default, 1.0, default))
                assert_aspect_3d([0.1, 0.2, 0.3], [0.1, 0.2, 0.3], [0.5, 100.0, -0.2], (1.0, 1.0, default))
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
            ui = UI.UIElements(dataset)
            labels = Plotting.FigureLabels(ui.state, dataset)
            (labels, ui.state, dataset)
        end

        @testset "Default Labels" begin
            # Arrange
            (labels, state, dataset) = init_figure_labels()

            # Assert
            @test labels.title[] == "1d_float"
            @test labels.xlabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.ylabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.zlabel[] == Constants.NOT_SELECTED_LABEL

            # Cleanup
            cleanup(dataset)
        end

        @testset "Updated Labels" begin
            # Arrange
            (labels, state, dataset) = init_figure_labels()

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

            # Cleanup
            cleanup(dataset)
        end
    end

    # ============================================
    #  Plot Data
    # ============================================

    @testset "Plot Data" begin
        # Arrange - helper function
        function init_plot_data()
            dataset = make_temp_dataset()
            ui = UI.UIElements(dataset)

            plot_data = Plotting.PlotData(ui.state, dataset)
            (plot_data, ui.state, dataset)
        end

        @testset "Types" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()

            # Assert
            @test plot_data isa Plotting.PlotData
            @test plot_data.plot_type isa Observable{Plotting.Plot}
            @test plot_data.sel_dims isa Observable{Vector{String}}
            @test plot_data.x isa Observable
            @test plot_data.y isa Observable
            @test plot_data.z isa Observable
            @test plot_data.d isa Vector
            @test plot_data.labels isa Plotting.FigureLabels

            # Cleanup
            cleanup(dataset)
        end

        @testset "Initial Values" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES[Constants.NOT_SELECTED_LABEL]
            @test plot_data.sel_dims[] == String[]
            @test plot_data.x[] == collect(Float64, 1:1)
            @test plot_data.y[] == collect(Float64, 1:1)
            @test plot_data.z[] == collect(Float64, 1:1)
            for i in 1:3
                @test plot_data.d[i] isa Observable
                @test plot_data.d[i][] === nothing
            end

            # cleanup
            cleanup(dataset)
        end

        @testset "Selected Dimensions" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
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

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Arrays 1D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.plot_type_name[] = "line"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["line"]
            @test plot_data.sel_dims[] == ["lon"]
            @test plot_data.d[1][].size == (5,)
            @test plot_data.d[2][] === nothing
            @test plot_data.d[3][] === nothing

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Arrays 2D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
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

            # cleanup
            cleanup(dataset)
        end
            
        @testset "Data Arrays 3D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
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

            # cleanup
            cleanup(dataset)
        end

        @testset "Data at Dimension Change" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act
            state.x_name[] = "only_unit"

            # Assert
            @test plot_data.sel_dims[] == ["only_unit", "lat"]
            @test plot_data.d[2][].size == (3, 7)

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Update Switch" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
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

            # cleanup
            cleanup(dataset)
        end

    end

    # ============================================
    #  Figure Data
    # ============================================

    @testset "Figure Data" begin
            

        @testset "Types" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()

            # Assert
            @test fig_data isa Plotting.FigureData
            @test fig_data.fig isa Figure
            @test fig_data.plot_data isa Plotting.PlotData
            @test fig_data.ax isa Observable{Union{Makie.AbstractAxis, Nothing}}
            @test fig_data.plot_obj isa Observable{Union{Makie.AbstractPlot, Nothing}}
            @test fig_data.cbar isa Observable{Union{Colorbar, Nothing}}
            @test fig_data.settings isa Plotting.FigureSettings

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 1D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 2D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 2D with 3D Axis" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 3D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Change Plot Type" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Change Plot Dimension" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
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

            # Cleanup
            cleanup(dataset)
        end

        @testset "Apply Kwargs" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)
            kwarg_text = fig_data.ui.main_menu.plot_menu.plot_kw.stored_string

            # Act - set some kwargs
            kwarg_text[] = "colorrange = (0.2, 0.8), colormap=:ice, titlevisible = false, label=\"My Label\"";

            # wait until all tasks are finished
            [wait(t) for t in fig_data.tasks[]]

            # Assert
            @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
            @test fig_data.plot_obj[].colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false
            @test fig_data.cbar[].label[] == "My Label"

            # Act - change to a 3D plot type
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"
            Plotting.create_axis!(fig_data, state)

            # wait until all tasks are finished
            [wait(t) for t in fig_data.tasks[]]

            # Assert - the kwargs should still apply
            @test fig_data.plot_obj[].colorrange.parent.value == (0.2, 0.8)
            @test fig_data.plot_obj[].colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false
            @test fig_data.cbar[].label[] == "My Label"

            # Cleanup
            cleanup(dataset)
        end
        @testset "Apply Bad Kwargs" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "contour"
            kwarg_text = fig_data.ui.main_menu.plot_menu.plot_kw.stored_string
            Plotting.create_axis!(fig_data, state)

            # Act & Assert - set nonexistent kwarg
            @test_logs (:warn, r"Property nonexistent not found in any plot object") begin
                kwarg_text[] = "nonexistent = 123, colormap = :ice"
                [wait(t) for t in fig_data.tasks[]]
            end

            # Cleanup
            cleanup(dataset)
        end


    end

    # ============================================
    #  Figure Settings
    # ============================================

    @testset "FiguresSettings" begin

        @testset "Resize Figure" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "contour")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
            settings = fd.settings

            # Assert default size
            @test settings.figsize[] == Constants.FIGSIZE

            # Act - resize figure via method
            new_size = (100, 100)
            Plotting.resize_figure!(fd, new_size)
            
            # Assert
            function assert_fig_size(fig, expected_size)
                actual_size = fig.scene.viewport[].widths
                @test actual_size == [expected_size[1], expected_size[2]]
                @test settings.figsize[] == expected_size
            end
            assert_fig_size(fd.fig, new_size)

            # resize figure via apply_figure_settings!
            new_size2 = (300, 150)
            Plotting.apply_figure_settings!(fd, :figsize, new_size2)
            assert_fig_size(fd.fig, new_size2)

            # resize figure via kwarg
            kwarg_text[] = "figsize = $(new_size)"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished
            assert_fig_size(fd.fig, new_size)

            # resize figure with bad value
            @test_warn "Figsize must be a tuple of two integers" begin
                Plotting.apply_figure_settings!(fd, :figsize, (100.0, 200.0)) # wrong type
                assert_fig_size(fd.fig, new_size)  # figsize should not have changed
            end

            @test_warn "Figsize must be a tuple of two integers" begin
                Plotting.apply_figure_settings!(fd, :figsize, (100, 200, 300))  # wrong length
                assert_fig_size(fd.fig, new_size)  # figsize should not have changed
            end

            # Cleanup
            cleanup(dataset)
        end

        @testset "cbar kwarg" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Assert Check that a colorbar is present
            @test fd.cbar[] isa Colorbar

            # Act - remove colorbar via kwarg
            kwarg_text[] = "cbar = false"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.cbar[] === nothing

            # Act - add colorbar via kwarg
            kwarg_text[] = "cbar = true"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.cbar[] isa Colorbar

            # Act - set to non-Bool value
            kwarg_text[] = "cbar = 123"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.cbar[] isa Colorbar  # should not have changed

            # Act - change to a plot type that does not support colorbar
            kwarg_text[] = ""
            state.plot_type_name[] = "line"
            Plotting.create_axis!(fd, state)

            # Assert Check that no colorbar is present
            @test fd.cbar[] === nothing

            # Cleanup
            cleanup(dataset)
        end

    end

    # ============================================
    #  Unit Tests
    # ============================================

    @testset "Unit Tests" begin
        @testset "kwarg_dict_to_string" begin
            # Arrange
            d = OrderedDict(:a => 1,
                     :b => 2.5,
                     :c => "test",
                     :d => :symbol,
                     :e => [1, 2, 3],
                     :f => (1, 2),
                     :g => 1:5,
                     :h => nothing,
                     )

            # Act
            s = Plotting.kwarg_dict_to_string(d)

            # Assert
            @test occursin("a=1", s)
            @test occursin("b=2.5", s)
            @test occursin("c=\"test\"", s)
            @test occursin("d=:symbol", s)
            @test occursin("e=[1, 2, 3]", s)
            @test occursin("f=(1, 2)", s)
            @test occursin("g=1:5", s)
            @test occursin("h=nothing", s)
            @test Plotting.kwarg_dict_to_string(OrderedDict{Symbol, Any}()) == ""
        end
    end

end