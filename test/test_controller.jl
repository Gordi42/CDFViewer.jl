using Test
using GLMakie
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller

@testset "Controller.jl" begin

    function init_default_controller()
        dataset = make_temp_dataset()
        controller = Controller.init_controller(dataset)
        # display(controller.fd.fig)
        Controller.setup_controller!(controller)
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

    function assert_controller_state(controller, variable, plot_class, expected_dims)
        # Test variable selection
        @test controller.ui.state.variable[] == variable
        # Test the plot object type
        @test controller.fd.plot_obj[] isa plot_class
        # Test the dimension options
        coord_menus = controller.ui.coord_menu.menus
        for menu in coord_menus
            @test menu.options[] == [Constants.NOT_SELECTED_LABEL; get_dims(variable)]
        end
        # Test the selected dimensions
        state = controller.ui.state
        @test state.x_name[] == (length(expected_dims) ≥ 1 ? expected_dims[1] : Constants.NOT_SELECTED_LABEL)
        @test state.y_name[] == (length(expected_dims) ≥ 2 ? expected_dims[2] : Constants.NOT_SELECTED_LABEL)
        @test state.z_name[] == (length(expected_dims) == 3 ? expected_dims[3] : Constants.NOT_SELECTED_LABEL)
    end

    @testset "Unit Tests" begin
    end

    @testset "Plot Selection" begin
        @testset "1D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "scatter"

            # Assert
            assert_controller_state(controller, "5d_float", Scatter, ["lon"])
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"])
        end

        @testset "1D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"])
        end

        @testset "2D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"])
        end

        @testset "2D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "contourf"

            # Assert
            assert_controller_state(controller, "5d_float", Contourf, ["lon", "lat"])
        end

        @testset "2D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "volume"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"])
        end

        @testset "3D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "line"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"])
        end

        @testset "3D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"])
        end

        @testset "3D → 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            plot_type[] = "contour3d"

            # Assert
            assert_controller_state(controller, "5d_float", Contour, ["lon", "lat", "float_dim"])
        end

        @testset "2D → Info" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            plot_type[] = "Info"

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[])
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
            assert_controller_state(controller, "only_long_var", Lines, ["lat"])
        end

        @testset "1D → 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "2d_float"
            plot_type[] = "heatmap"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"])
        end

        @testset "2D → 5D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_gap", plot="heatmap")

            # Act
            var_name[] = "5d_float"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"])
        end

        @testset "5D → 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            var_name[] = "only_long_var"

            # Assert
            assert_controller_state(controller, "only_long_var", Lines, ["lat"])
        end

        @testset "String Variable" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="line")

            # Act
            var_name[] = "string_var"

            # Assert
            assert_controller_state(controller, "string_var", Nothing, String[])
            @test controller.fd.plot_obj[] === nothing
            @test controller.ui.state.plot_type_name[] == "Info"
        end

        @testset "2D → 2D [Different Dims]" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="heatmap")

            # Act
            var_name[] = "2d_gap"
            
            # Assert
            assert_controller_state(controller, "2d_gap", Heatmap, ["lon", "float_dim"])
        end

    end

    @testset "Dimension Selection" begin

        @testset "Same Dimension" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = "float_dim"
            dim_names[2][] = "only_unit"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["float_dim", "only_unit"])
        end

        @testset "Switch Dimensions" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = "lat"
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "lon"])
        end

        @testset "Remove x from 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="line")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Nothing, String[])
        end

        @testset "Remove x from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lat"])
        end

        @testset "Remove y from 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"])
        end

        @testset "Remove x from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[1][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lat", "float_dim"])
        end

        @testset "Remove y from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[2][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "float_dim"])
        end

        @testset "Remove z from 3D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="volume")

            # Act
            dim_names[3][] = Constants.NOT_SELECTED_LABEL

            # Assert
            assert_controller_state(controller, "5d_float", Heatmap, ["lon", "lat"])
        end

        @testset "Select dimension doubled" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "5d_float", Lines, ["lon"])
        end

        @testset "Add x to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="Info")

            # Act
            dim_names[1][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Lines, ["lon"])
        end

        @testset "Add y to 0D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="1d_float", plot="Info")

            # Act
            dim_names[2][] = "lon"

            # Assert
            assert_controller_state(controller, "1d_float", Lines, ["lon"])
        end

        @testset "Add y to 1D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="2d_float", plot="line")

            # Act
            dim_names[2][] = "lat"

            # Assert
            assert_controller_state(controller, "2d_float", Heatmap, ["lon", "lat"])
        end

        @testset "Add z to 2D" begin
            # Arrange
            controller, var_name, plot_type, dim_names = setup_controller(var="5d_float", plot="heatmap")

            # Act
            dim_names[3][] = "float_dim"

            # Assert
            assert_controller_state(controller, "5d_float", Volume, ["lon", "lat", "float_dim"])
        end

    end

end
