using Test
using GLMakie
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller

NS = Constants.NOT_SELECTED_LABEL


@testset "Controller.jl" begin

    function init_default_controller()
        Controller.ViewerController(make_temp_dataset(), headless=true)
    end

    function setup_controller(;var::String = "1d_float", plot::String = "line")
        # Initialize the controller
        controller = init_default_controller()

        # Get references to the relevant UI components
        var_menu = controller.ui.main_menu.variable_menu
        pt_menu = controller.ui.main_menu.plot_menu.plot_type
        dim_menus = controller.ui.main_menu.coord_menu.menus

        # Create observables to control the selections
        var_name = Observable(var_menu.selection[])
        plot_type = Observable(pt_menu.selection[])
        dim_names = [Observable(menu.selection[]) for menu in dim_menus]

        # Set up listeners to update the UI components when the observables change
        on(var_name) do v
            var_menu.i_selected[] = findfirst(==(v), var_menu.options[])
        end

        on(plot_type) do pt
            pt_menu.i_selected[] = findfirst(==(pt), pt_menu.options[])
        end

        for (menu, dim_name) in zip(dim_menus, dim_names)
            on(dim_name) do sel
                menu.i_selected[] = findfirst(==(sel), menu.options[])
            end
        end

        # Set the initial variable and plot type
        var_name[] = var
        plot_type[] = plot

        (controller, var_name, plot_type, dim_names)
    end

    function assert_controller_state(
        controller,
        variable,
        plot_class,
        expected_dims,
        expected_play_dim;
        export_string = "",
        )
        # Test variable selection
        @test controller.ui.state.variable[] == variable
        # Test the plot object type
        @test controller.fd.plot_obj[] isa plot_class
        # Test the dimension options
        coord_menus = controller.ui.main_menu.coord_menu.menus
        for menu in coord_menus
            @test menu.options[] == [NS; get_dims(variable)]
        end
        # Test the selected dimensions
        state = controller.ui.state
        @test state.x_name[] == (length(expected_dims) ≥ 1 ? expected_dims[1] : NS)
        @test state.y_name[] == (length(expected_dims) ≥ 2 ? expected_dims[2] : NS)
        @test state.z_name[] == (length(expected_dims) == 3 ? expected_dims[3] : NS)
        # Test the playback menu
        play_menu = controller.ui.main_menu.playback_menu.var
        open_dims = setdiff(get_dims(variable), expected_dims)
        @test setdiff(play_menu.options[], [NS; open_dims...]) == []
        @test play_menu.selection[] == expected_play_dim
        # Test the export string
        if export_string isa Regex
            @test occursin(export_string, Controller.get_export_string(controller))
        end
    end

    function cleanup(controller)
        GLMakie.closeall()
        close(controller.dataset.ds)
    end

    @testset "Plot Selection" begin
        @testset "1D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "scatter"

            # Assert
            assert_controller_state(controller, "5d_float", Scatter, ["lon"], "only_long",
                export_string=r"-v5d_float -xlon -pscatter")
            
            # Cleanup
            cleanup(controller)
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long",
                export_string=r"-v5d_float -xlon -ylat -pheatmap")

            # Cleanup
            cleanup(controller)
        end

        @testset "1D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "contourf"

            # Assert
            assert_controller_state(controller, "5d_float", Contourf, ["lon", "lat"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "3D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "3D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "3D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "contour3d"

            # Assert
            assert_controller_state(controller, "5d_float", Contour, ["lon", "lat", "float_dim"], "only_long",
                export_string=r"-v5d_float -xlon -ylat -zfloat_dim -pcontour3d")

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → Select" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[], "only_long")
            @test controller.fd.ax[] === nothing
            @test controller.fd.cbar[] === nothing

            # Cleanup
            cleanup(controller)
        end

    end

    @testset "Variable Selection" begin

        @testset "1D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "only_long_var"

            # Assert
            assert_controller_state(controller, "only_long_var", Lines, ["lat"], NS,
                export_string="-vonly_long_var -xlat -pline")

            # Cleanup
            cleanup(controller)
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "2d_float"
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"], NS)

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → 5D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_gap", plot="heatmap")

            # Act
            var_name[] = "5d_float"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "5D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            var_name[] = "only_long_var"

            # Assert
            assert_controller_state(controller, "only_long_var", Lines, ["lat"], NS)

            # Cleanup
            cleanup(controller)
        end

        @testset "String Variable" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "string_var"

            # Assert
            assert_controller_state(controller, "string_var", Nothing, String[], "string_dim")
            @test controller.fd.plot_obj[] === nothing
            @test controller.ui.state.plot_type_name[] == Constants.NOT_SELECTED_LABEL

            # Cleanup
            cleanup(controller)
        end

        @testset "2D → 2D [Different Dims]" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")

            # Act
            var_name[] = "2d_gap"
            
            # Assert
            assert_controller_state(controller, "2d_gap", Heatmap, ["lon", "float_dim"], NS)

            # Cleanup
            cleanup(controller)
        end

    end

    @testset "Dimension Selection" begin

        @testset "Same Dimension" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = "float_dim"
            dim_names[2][] = "only_long"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["float_dim", "only_long"], "only_unit")
            @test all(Point2f(xi, yi) in controller.fd.ax[].finallimits[]
                            for xi in controller.fd.plot_data.x[], yi in controller.fd.plot_data.y[])

            # Cleanup
            cleanup(controller)
        end

        @testset "Switch Dimensions" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = "lat"
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "lon"], "only_long",
                export_string=r"-v5d_float -xlat -ylon -pheatmap")
            @test all(Point2f(xi, yi) in controller.fd.ax[].finallimits[]
                            for xi in controller.fd.plot_data.x[], yi in controller.fd.plot_data.y[])

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove x from 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove x from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lat"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove y from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove x from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove y from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Remove z from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[3][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Select dimension doubled" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Add x to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(
                var="1d_float", plot=Constants.NOT_SELECTED_LABEL)

            # Act
            dim_names[1][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Nothing, ["lon"], NS)

            # Cleanup
            cleanup(controller)
        end

        @testset "Add y to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(
                var="1d_float", plot=Constants.NOT_SELECTED_LABEL)

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Nothing, ["lon"], NS)

            # Cleanup
            cleanup(controller)
        end

        @testset "Add y to 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="line")

            # Act
            dim_names[2][] = "lat"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"], NS)

            # Cleanup
            cleanup(controller)
        end

        @testset "Add z to 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[3][] = "float_dim"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")

            # Cleanup
            cleanup(controller)
        end

        @testset "Check Auto Limits" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")
            dim_names[2][] = "float_dim"

            # Act
            dim_names[2][] = "lat"

            # Assert
            @test all(Point2f(xi, yi) in controller.fd.ax[].finallimits[]
                            for xi in controller.fd.plot_data.x[], yi in controller.fd.plot_data.y[])

            # Act
            dim_names[2][] = "lon"
            dim_names[1][] = "lat"
            @test all(Point2f(xi, yi) in controller.fd.ax[].finallimits[]
                            for xi in controller.fd.plot_data.x[], yi in controller.fd.plot_data.d[1][])

            # Cleanup
            cleanup(controller)
        end

    end

    @testset "Playback Selection" begin
        # Arrange
        controller, var_name, plot_type, dim_names = setup_controller(var="4d_float", plot="heatmap")
        play_menu = controller.ui.main_menu.playback_menu.var

        # Assert: should start with "time" as the playback dimension
        assert_controller_state(controller, "4d_float", Heatmap, ["lon", "lat"], "time")

        # Act: change the playback dimension and variable
        play_menu.i_selected[] = findfirst(==("float_dim"), play_menu.options[])
        var_name[] = "5d_float"

        # Assert
        assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "float_dim",
            export_string=r"-afloat_dim")

        # Cleanup
        cleanup(controller)
    end
    @testset "Keyword Settings" begin
        @testset "levels keyword for contour" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour")
            kwarg_text = controller.fd.ui.main_menu.plot_menu.plot_kw.stored_string

            kwarg_text[] = "levels=10, labels=true"

            # wait until all tasks are finished
            [wait(t) for t in controller.fd.tasks[]]

            # Assert
            @test controller.fd.plot_obj[].levels[] == 10
            @test controller.fd.plot_obj[].labels[] == true
            exp_str = Controller.get_export_string(controller)
            @test occursin(r"--kwargs='levels=10, labels=true", exp_str)

            # Cleanup
            cleanup(controller)
        end

        @testset "Axis keywords" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_gap", plot="heatmap")
            kwarg_text = controller.fd.ui.main_menu.plot_menu.plot_kw.stored_string

            kwarg_text[] = "limits=(nothing, nothing, 1, 3), xscale=log10"

            # wait until all tasks are finished
            [wait(t) for t in controller.fd.tasks[]]

            # Assert
            @test controller.fd.ax[].limits[] == (nothing, nothing, 1, 3)
            @test controller.fd.ax[].xscale[] == log10

            # Cleanup
            cleanup(controller)
        end

        @testset "Invalid keyword" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour")
            kwarg_text = controller.fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Act & Assert: should issue a warning about the invalid keyword
            @test_warn "Property invalid_kw not found in any plot object" begin
                kwarg_text[] = "invalid_kw=123, levels=5, colormap=:balance"

                # wait until all tasks are finished
                [wait(t) for t in controller.fd.tasks[]]
            end

            # Assert: should apply only the valid keyword
            @test controller.fd.plot_obj[].levels[] == 5

            # Act & Assert: should issue a warning about the invalid value
            @test_warn "An error occurred while applying keyword arguments" begin
                kwarg_text[] = "levels=not_a_number, colormap=:viridis"
                # wait until all tasks are finished
                [wait(t) for t in controller.fd.tasks[]]
            end

            # Assert: should revert to original settings
            @test controller.fd.plot_obj[].levels[] == 5
            @test controller.fd.plot_obj[].colormap[] == :balance

            # Cleanup
            cleanup(controller)
        end

        @testset "Figsize and Colorbar" begin
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")
            kwarg_text = controller.fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Act: change the figure size
            kwarg_text[] = "figsize=(200, 200)"
            # wait until all tasks are finished
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the figure size
            actual_size = controller.fd.fig.scene.viewport[].widths
            @test actual_size == [200, 200]
            @test controller.fd.settings.figsize[] == (200, 200)

            # Cleanup
            cleanup(controller)
        end

        @testset "Interpolation Ranges" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")
            rc = controller.ui.state.range_control[]
            kwarg_text = controller.fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Act: set the interpolation ranges to StepRange
            kwarg_text[] = "lon=-2:0.5:2"
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the interpolation ranges
            @test rc.lon == -2:0.5:2
            @test controller.fd.plot_data.x[] == collect(-2:0.5:2)
            @test size(controller.fd.plot_data.d[2][]) == (length(rc.lon), length(rc.lat))

            # Act: set the interpolation ranges to Range
            kwarg_text[] = "lon=0:4"
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the interpolation ranges
            @test rc.lon == 0:4
            @test controller.fd.plot_data.x[] == collect(0:4)
            @test size(controller.fd.plot_data.d[2][]) == (length(rc.lon), length(rc.lat))

            # Act: set the interpolation ranges to Vector
            kwarg_text[] = "lon=[-1, 0, 1]"
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the interpolation ranges
            @test rc.lon == [-1, 0, 1]
            @test controller.fd.plot_data.x[] == [-1, 0, 1]
            @test size(controller.fd.plot_data.d[2][]) == (length(rc.lon), length(rc.lat))

            # Act: set the interpolation ranges to Tuple
            kwarg_text[] = "lon=(-1, 0, 10)"
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the interpolation ranges
            @test rc.lon == LinRange(-1, 0, 10)
            @test controller.fd.plot_data.x[] == collect(LinRange(-1, 0, 10))
            @test size(controller.fd.plot_data.d[2][]) == (length(rc.lon), length(rc.lat))

            # Act: set the interpolation ranges to nothing
            kwarg_text[] = "lon=nothing"
            [wait(t) for t in controller.fd.tasks[]]

            # Assert: should update the interpolation ranges
            @test rc.lon ≈ rc.interp.ds["lon"][:]
            @test controller.fd.plot_data.x[] == rc.interp.ds["lon"][:]
            @test size(controller.fd.plot_data.d[2][]) == (length(rc.lon), length(rc.lat))

            # Cleanup
            cleanup(controller)
        end

    end

    @testset "Export String" begin
        function assert_export(controller, expected_substrs::Vector{Regex})
            exp_str = Controller.get_export_string(controller)
            for substr in expected_substrs
                @test occursin(substr, exp_str)
            end
        end

        @testset "No Axis" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot=Constants.NOT_SELECTED_LABEL)

            # Assert
            assert_export(controller, [r"-v1d_float"])

            # Cleanup
            cleanup(controller)
        end

        @testset "2D Axis" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour")

            # Assert
            assert_export(controller, [r"-v2d_float", r"-xlon", r"-ylat", r"-pcontour", r"limits="])

            # Cleanup
            cleanup(controller)
        end

        @testset "3D Axis" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="3d_float", plot="surface")

            # Assert
            assert_export(controller, [r"-v3d_float", r"-xlon", r"-ylat", r"-psurface", r"limits=", r"azimuth=", r"elevation="])

            # Cleanup
            cleanup(controller)
        end

        @testset "Change figsize" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour");

            # Act
            resize!(controller.fd.fig, 300, 400);

            # Assert
            assert_export(controller, [r"figsize=\(300, 400\)"])

            # Cleanup
            cleanup(controller)
        end
    end

    @testset "Window Closing" begin
        # Arrange
        controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour")
        fig_screen = controller.fig_screen
        fig = controller.fd.fig

        # Assert: check if the figure is connected
        @test fig_screen[].scene === fig.scene

        # Act: Close the window
        close(fig_screen[])

        # Assert: check if the figure is disconnected
        @test fig_screen[].scene !== fig.scene
        @test controller.ui.state.plot_type_name[] === Constants.NOT_SELECTED_LABEL

        # Act: Change the plot type to see if it recreates the figure
        plot_type[] = "heatmap"

        # Assert: check if the figure is reconnected
        @test fig_screen[].scene === fig.scene

        # Act: Close the window again
        close(fig_screen[])

        # Assert: check if the figure is disconnected again
        @test fig_screen[].scene !== fig.scene
        @test controller.ui.state.plot_type_name[] === Constants.NOT_SELECTED_LABEL

        # Cleanup
        cleanup(controller)
    end
end
