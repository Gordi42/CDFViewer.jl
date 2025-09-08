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
        controller = Controller.ViewerController(make_temp_dataset())
        screen = GLMakie.Screen(visible=false)
        display(screen, controller.fd.fig)
        Controller.setup!(controller)
        controller
    end

    function setup_controller(;var::String = "1d_float", plot::String = "line")
        # Initialize the controller
        controller = init_default_controller()

        # Get references to the relevant UI components
        var_menu = controller.ui.main_menu.variable_menu
        pt_menu = controller.ui.main_menu.plot_menu.plot_type
        dim_menus = controller.ui.coord_menu.menus

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

    function assert_controller_state(controller, variable, plot_class, expected_dims, expected_play_dim)
        # Test variable selection
        @test controller.ui.state.variable[] == variable
        # Test the plot object type
        @test controller.fd.plot_obj[] isa plot_class
        # Test the dimension options
        coord_menus = controller.ui.coord_menu.menus
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
    end

    @testset "Plot Selection" begin
        @testset "1D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "scatter"

            # Assert
            assert_controller_state(controller, "5d_float", Scatter, ["lon"], "only_long")
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long")
        end

        @testset "1D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")
        end

        @testset "2D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")
        end

        @testset "2D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "contourf"

            # Assert
            assert_controller_state(controller, "5d_float", Contourf, ["lon", "lat"], "only_long")
        end

        @testset "2D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")
        end

        @testset "3D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")
        end

        @testset "3D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long")
        end

        @testset "3D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "contour3d"

            # Assert
            assert_controller_state(controller, "5d_float", Contour, ["lon", "lat", "float_dim"], "only_long")
        end

        @testset "2D → Info" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "Info"

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[], "only_long")
            @test controller.fd.ax[] === nothing
            @test controller.fd.cbar[] === nothing
        end

    end

    @testset "Variable Selection" begin

        @testset "1D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "only_long_var"

            # Assert
            assert_controller_state(controller, "only_long_var", Lines, ["lat"], NS)
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "2d_float"
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"], NS)
        end

        @testset "2D → 5D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_gap", plot="heatmap")

            # Act
            var_name[] = "5d_float"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"], "only_long")
        end

        @testset "5D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            var_name[] = "only_long_var"

            # Assert
            assert_controller_state(controller, "only_long_var", Lines, ["lat"], NS)
        end

        @testset "String Variable" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "string_var"

            # Assert
            assert_controller_state(controller, "string_var", Nothing, String[], "string_dim")
            @test controller.fd.plot_obj[] === nothing
            @test controller.ui.state.plot_type_name[] == "Info"
        end

        @testset "2D → 2D [Different Dims]" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")

            # Act
            var_name[] = "2d_gap"
            
            # Assert
            assert_controller_state(controller, "2d_gap", Heatmap, ["lon", "float_dim"], NS)
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
        end

        @testset "Switch Dimensions" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = "lat"
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "lon"], "only_long")
            @test all(Point2f(xi, yi) in controller.fd.ax[].finallimits[]
                            for xi in controller.fd.plot_data.x[], yi in controller.fd.plot_data.y[])
        end

        @testset "Remove x from 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[], "only_long")
        end

        @testset "Remove x from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lat"], "only_long")
        end

        @testset "Remove y from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")
        end

        @testset "Remove x from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "float_dim"], "only_long")
        end

        @testset "Remove y from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"], "only_long")
        end

        @testset "Remove z from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[3][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "only_long")
        end

        @testset "Select dimension doubled" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"], "only_long")
        end

        @testset "Add x to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="Info")

            # Act
            dim_names[1][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Lines, ["lon"], NS)
        end

        @testset "Add y to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="Info")

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Lines, ["lon"], NS)
        end

        @testset "Add y to 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="line")

            # Act
            dim_names[2][] = "lat"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"], NS)
        end

        @testset "Add z to 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[3][] = "float_dim"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"], "only_long")
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
        assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"], "float_dim")
    end

    @testset "Keyword Settings" begin
        @testset "levels keyword for contour" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="contour")

            controller.ui.state.plot_kw[] = "levels=10, labels=true"

            # wait until all tasks are finished
            [wait(t) for t in controller.fd.tasks[]]

            # Assert
            @test controller.fd.plot_obj[].levels[] == 10
            @test controller.fd.plot_obj[].labels[] == true
        end

        @testset "Axis keywords" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")

            controller.ui.state.plot_kw[] = "limits=(nothing, nothing, 1, 3), xscale=log10"

            # wait until all tasks are finished
            [wait(t) for t in controller.fd.tasks[]]

            # Assert
            @test controller.fd.ax[].limits[] == (nothing, nothing, 1, 3)
            @test controller.fd.ax[].xscale[] == log10
        end
    end
end
