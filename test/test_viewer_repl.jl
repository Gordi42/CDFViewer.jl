using Test

using GLMakie
using Suppressor
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller
using CDFViewer.Parsing
using CDFViewer.ViewerREPL

@testset "ViewerREPL.jl" begin
    function init_state()
        controller = Controller.ViewerController(make_temp_dataset(), headless=true)
        ViewerREPL.REPLState(controller)
    end

    function cleanup(state)
        GLMakie.closeall()
        close(state.controller.dataset.ds)
    end

    @testset "Helpers" begin
        @testset "select_menu_option" begin
            # Arrange
            state = init_state()
            menu = Menu(Figure(), options=["a", "b", "c"])

            # Act & Assert
            @test ViewerREPL.select_menu_option!(menu, "cmd b") == "Selected: b"
            @test menu.i_selected[] == 2
            @test menu.selection[] == "b"
            @test_warn "Invalid selection:" begin
                @test ViewerREPL.select_menu_option!(menu, "cmd d") == "Available options: \na, b, c"
            end

            # Cleanup
            cleanup(state)
        end

    end

    @testset "Command Implementations" begin
        @testset "Select Variable" begin
            # Arrange
            state = init_state()

            # Act & Assert: Select invalid variable
            @test_warn "Invalid selection:" begin
                ViewerREPL.select_variable(state, "var invalid_var")
            end

            # Act & Assert: Select via function
            @test ViewerREPL.select_variable(state, "v 5d_float") == "Selected: 5d_float"
            @test state.controller.ui.state.variable[] == "5d_float"

            # Act & Assert: Select via evaluate_command
            @test ViewerREPL.evaluate_command(state, "v 4d_float") == "Selected: 4d_float"
            @test state.controller.ui.state.variable[] == "4d_float"

            # Cleanup
            cleanup(state)
        end

        @testset "Select Plot Type" begin
            # Arrange
            state = init_state()

            # Act & Assert: Select invalid plot type
            @test_warn "Invalid selection:" begin
                ViewerREPL.select_plot_type(state, "plot invalid_plot")
            end

            # Act & Assert: Select via function
            @test ViewerREPL.select_plot_type(state, "p line") == "Selected: line"
            @test state.controller.ui.state.plot_type_name[] == "line"

            # Act & Assert: Select via evaluate_command
            @test ViewerREPL.evaluate_command(state, "p scatter") == "Selected: scatter"
            @test state.controller.ui.state.plot_type_name[] == "scatter"

            # Cleanup
            cleanup(state)
        end

        @testset "Select x axis" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act & Assert: Select invalid axis
            @test_warn "Invalid selection:" begin
                ViewerREPL.select_x_axis(state, "x invalid_axis")
            end

            # Act & Assert: Select via function
            @test ViewerREPL.select_x_axis(state, "x lon") == "Selected: lon"
            @test state.controller.ui.state.x_name[] == "lon"

            # Act & Assert: Select via evaluate_command
            @test ViewerREPL.evaluate_command(state, "x lat") == "Selected: lat"
            @test state.controller.ui.state.x_name[] == "lat"

            # Cleanup
            cleanup(state)
        end

        @testset "Select y axis" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act & Assert: Select invalid axis
            @test_warn "Invalid selection:" begin
                ViewerREPL.select_y_axis(state, "y invalid_axis")
            end

            # Act & Assert: Select via function
            @test ViewerREPL.select_y_axis(state, "y lat") == "Selected: lat"
            @test state.controller.ui.state.x_name[] == "lat"

            # Act & Assert: Select via evaluate_command
            @test ViewerREPL.evaluate_command(state, "y lon") == "Selected: lon"
            @test state.controller.ui.state.y_name[] == "lon"

            # Cleanup
            cleanup(state)
        end

        @testset "Select z axis" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act & Assert: Select invalid axis
            @test_warn "Invalid selection:" begin
                ViewerREPL.select_z_axis(state, "z invalid_axis")
            end

            # Act & Assert: Select via function
            @test ViewerREPL.select_z_axis(state, "z lon") == "Selected: lon"
            @test ViewerREPL.select_z_axis(state, "z lat") == "Selected: lat"
            @test state.controller.ui.state.x_name[] == "lon"
            @test state.controller.ui.state.y_name[] == "lat"

            # Act & Assert: Select via evaluate_command
            @test ViewerREPL.evaluate_command(state, "z float_dim") == "Selected: float_dim"
            @test state.controller.ui.state.z_name[] == "float_dim"

            # Cleanup
            cleanup(state)
        end

        @testset "Select index" begin
            # Arrange
            state = init_state()
            
            # Act & Assert: Wrong Usage
            @test_warn "Usage:" begin
                @test ViewerREPL.select_index(state, "isel") == ""
            end
            @test_warn "Usage:" begin
                @test ViewerREPL.select_index(state, "isel 4") == ""
            end

            # Act & Assert: Invalid index
            @test_warn "Index must be an integer." begin
                @test ViewerREPL.select_index(state, "isel lon invalid_index") == ""
            end
            @test_warn "Index must be an integer." begin
                @test ViewerREPL.select_index(state, "isel lon 32.1") == ""
            end

            # Act & Assert: Invalid dimension
            @test_warn "Dimension" begin
                @test ViewerREPL.select_index(state, "isel invalid_dim 2") == ""
            end

            # Act & Assert: Index out of bounds
            @test_warn "Index out of range" begin
                @test ViewerREPL.select_index(state, "isel float_dim 100") == ""
            end
            @test_warn "Index out of range" begin
                @test ViewerREPL.select_index(state, "isel float_dim -5") == ""
            end

            # Act Select via function
            output = ViewerREPL.select_index(state, "isel float_dim 2")

            # Assert
            @test occursin("float_dim", output)
            slider = state.controller.ui.main_menu.coord_sliders.sliders["float_dim"]
            @test slider.value[] == 2

            # Act & Assert: Select via evaluate_command
            ViewerREPL.evaluate_command(state, "isel float_dim 3")
            @test slider.value[] == 3

            # Cleanup
            cleanup(state)
        end

        @testset "Select Value" begin
            # Arrange
            state = init_state()

            # Act & Assert: Wrong Usage
            @test_warn "Usage:" begin
                @test ViewerREPL.select_value(state, "sel") == ""
            end
            @test_warn "Usage:" begin
                @test ViewerREPL.select_value(state, "sel 4") == ""
            end

            # Act & Assert: Invalid value
            @test_warn "Value must be a number." begin
                @test ViewerREPL.select_value(state, "sel lon invalid_value") == ""
            end

            # Act & Assert: Invalid dimension
            @test_warn "Dimension" begin
                @test ViewerREPL.select_value(state, "sel invalid_dim 2") == ""
            end

            # Act Select via function
            output = ViewerREPL.select_value(state, "sel float_dim 1.4")

            # Assert
            @test occursin("float_dim: 1.4", output)
            slider = state.controller.ui.main_menu.coord_sliders.sliders["float_dim"]
            @test slider.value[] == 3  # third value is 1.4

            # Act & Assert: Select via evaluate_command
            ViewerREPL.evaluate_command(state, "sel float_dim 10.0")
            @test slider.value[] == 6  # last value is 2.0

            ViewerREPL.evaluate_command(state, "sel float_dim -10.0")
            @test slider.value[] == 1  # first value is 1.0

            # Cleanup
            cleanup(state)
        end

        @testset "Toggle Play" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act & Assert: Activate Play
            @test ViewerREPL.toggle_play(state, "play") == "Playing."
            @test state.controller.ui.main_menu.playback_menu.toggle.active[] == true

            # Act & Assert: Deactivate Play
            @test ViewerREPL.toggle_play(state, "play") == "Paused."
            @test state.controller.ui.main_menu.playback_menu.toggle.active[] == false

            # Act & Assert: Set dimension while activating play
            @test ViewerREPL.toggle_play(state, "play float_dim") == "Playing."
            @test state.controller.ui.main_menu.playback_menu.toggle.active[] == true
            @test state.controller.ui.main_menu.playback_menu.var.selection[] == "float_dim"

            # Cleanup
            cleanup(state)
        end

        @testset "Set Play Speed" begin
            # Arrange
            state = init_state()
            slider = state.controller.ui.main_menu.playback_menu.speed

            # Act & Assert: Wrong Usage
            @test_warn "Speed must be a number." begin
                @test ViewerREPL.set_play_speed(state, "speed invalid") == ""
            end

            # Act & Assert: Current Speed
            @test ViewerREPL.set_play_speed(state, "speed") == "Current speed: 1.0"

            # Act: Set Speed via function
            output = ViewerREPL.set_play_speed(state, "speed 0.5")
            
            # Assert
            @test occursin("New speed:", output)
            @test isapprox(slider.value[], log10(0.5), atol=0.1)

            # Act & Assert: Set Speed via evaluate_command
            ViewerREPL.evaluate_command(state, "speed 2.0")
            @test isapprox(slider.value[], log10(2.0), atol=0.1)

            # Cleanup
            cleanup(state)
        end

        @testset "Set Play Dimension" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")
            menu = state.controller.ui.main_menu.playback_menu.var

            # Act & Assert: Invalid dimension
            @test_warn "Invalid selection:" begin
                ViewerREPL.set_play_dimension(state, "pdim invalid_dim")
            end
            @test_warn "Invalid selection:" begin
                ViewerREPL.set_play_dimension(state, "pdim time")
            end

            # Act & Assert: Set Dimension via function
            @test ViewerREPL.set_play_dimension(state, "pdim float_dim") == "Selected: float_dim"
            @test menu.selection[] == "float_dim"

            # Act & Assert: Set Dimension via evaluate_command
            @test ViewerREPL.evaluate_command(state, "pdim only_unit") == "Selected: only_unit"
            @test menu.selection[] == "only_unit"

            # Cleanup
            cleanup(state)
        end

        @testset "Save Figure" begin
            # Arrange
            state = init_state()
            output = state.controller.ui.state.output_settings[]
            ViewerREPL.select_plot_type(state, "p line")
            temp_filepath = tempname() * ".png"

            # Act & Assert: Save via function
            @test_logs (:info, "Saved figure to $temp_filepath") begin
                @test ViewerREPL.save_figure(state, "savefig filename=$temp_filepath") == ""
            end
            @test isfile(temp_filepath)
            @test output.filename == temp_filepath
            rm(temp_filepath)

            # Act & Assert: Save via evaluate_command
            @test_logs (:info, "Saved figure to $temp_filepath") begin
                @test ViewerREPL.evaluate_command(state, "savefig") == ""
            end
            @test isfile(temp_filepath)
            rm(temp_filepath)

            # Cleanup
            cleanup(state)
        end

        @testset "Record Movie" begin
            # Arrange
            state = init_state()
            output = state.controller.ui.state.output_settings[]
            ViewerREPL.select_variable(state, "v 5d_float")
            ViewerREPL.set_play_dimension(state, "pdim float_dim")
            ViewerREPL.select_plot_type(state, "p line")
            temp_filepath = tempname() * ".mkv"

            # Act & Assert: Record via function
            @suppress ViewerREPL.record_movie(state, "record filename=$temp_filepath, framerate=5")
            @test isfile(temp_filepath)
            rm(temp_filepath)
            @test output.filename == temp_filepath
            @test output.framerate == 5

            # Act & Assert: Record via evaluate_command
            @suppress ViewerREPL.evaluate_command(state, "record framerate=10")
            @test isfile(temp_filepath)
            rm(temp_filepath)
            @test output.filename == temp_filepath
            @test output.framerate == 10

            # Cleanup
            cleanup(state)
        end

        @testset "Show / Hide UI" begin
            # Arrange
            state = init_state()

            # Act & Assert: Show Figure
            @test ViewerREPL.show_figure(state, "show") == "Opened figure window."
            @test ViewerREPL.evaluate_command(state, "show") == "Opened figure window."

            # Act & Assert: Hide Figure
            @test ViewerREPL.hide_figure(state, "hide") == "Closed figure window."
            @test ViewerREPL.evaluate_command(state, "hide") == "Closed figure window."

            # Act & Assert: Show Menu
            @test ViewerREPL.show_menu(state, "menu") == "Opened menu window."
            @test ViewerREPL.evaluate_command(state, "menu") == "Opened menu window."

            # Act & Assert: Hide Menu
            @test ViewerREPL.hide_menu(state, "hidemenu") == "Closed menu window."
            @test ViewerREPL.evaluate_command(state, "hidemenu") == "Closed menu window."

            # Cleanup
            cleanup(state)
        end

        @testset "Get Figure Keywords" begin
            # Arrange
            state = init_state()

            # Act
            f1 = () -> ViewerREPL.get_figure_kwargs(state, "kwargs")
            f2 = () -> ViewerREPL.get_kwargs_list(state, "kwargs figure")
            f3 = () -> ViewerREPL.evaluate_command(state, "kwargs figure")
            f4 = () -> ViewerREPL.get_kwargs_list(state, "kwargs")
            f5 = () -> ViewerREPL.evaluate_command(state, "kwargs")

            for f in (f1, f2, f3, f4, f5)
                output = f()
                for (i, kw) in enumerate(propertynames(state.controller.fd.settings))
                    @test occursin(string(kw), output)
                    if i > 5  # Limit to first 5 to speed up tests
                        break
                    end
                end
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Axis Keywords" begin
            # Arrange
            state = init_state()
            f1 = () -> ViewerREPL.get_axis_kwargs(state, "kwargs")
            f2 = () -> ViewerREPL.get_kwargs_list(state, "kwargs axis")
            f3 = () -> ViewerREPL.evaluate_command(state, "kwargs axis")
            f4 = () -> ViewerREPL.get_kwargs_list(state, "kwargs")
            f5 = () -> ViewerREPL.evaluate_command(state, "kwargs")

            for f in (f1, f2, f3)
                # Act
                output = f()

                # Assert
                @test length(split(output, '\n')) == 2  # No axis yet
            end

            # Act: Create an axis
            ViewerREPL.select_plot_type(state, "p line")
            for f in (f1, f2, f3, f4, f5)
                output = f()
                for (i, kw) in enumerate(propertynames(state.controller.fd.ax[]))
                    @test occursin(string(kw), output)
                    if i > 5  # Limit to first 5 to speed up tests
                        break
                    end
                end
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Plot Keywords" begin
            # Arrange
            state = init_state()
            f1 = () -> ViewerREPL.get_plot_kwargs(state, "kwargs")
            f2 = () -> ViewerREPL.get_kwargs_list(state, "kwargs plot")
            f3 = () -> ViewerREPL.evaluate_command(state, "kwargs plot")
            f4 = () -> ViewerREPL.get_kwargs_list(state, "kwargs")
            f5 = () -> ViewerREPL.evaluate_command(state, "kwargs")

            for f in (f1, f2, f3)
                # Act
                output = f()

                # Assert
                @test length(split(output, '\n')) == 2  # No plot yet
            end

            # Act: Create a plot
            ViewerREPL.select_plot_type(state, "p line")
            for f in (f1, f2, f3, f4, f5)
                output = f()
                for (i, kw) in enumerate(propertynames(state.controller.fd.plot_obj[]))
                    @test occursin(string(kw), output)
                    if i > 5  # Limit to first 5 to speed up tests
                        break
                    end
                end
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Colorbar Keywords" begin
            # Arrange
            state = init_state()
            f1 = () -> ViewerREPL.get_colorbar_kwargs(state, "kwargs")
            f2 = () -> ViewerREPL.get_kwargs_list(state, "kwargs colorbar")
            f3 = () -> ViewerREPL.evaluate_command(state, "kwargs colorbar")
            f4 = () -> ViewerREPL.get_kwargs_list(state, "kwargs")
            f5 = () -> ViewerREPL.evaluate_command(state, "kwargs")

            for f in (f1, f2, f3)
                # Act
                output = f()

                # Assert
                @test length(split(output, '\n')) == 2  # No colorbar yet
            end

            # Act: Create a plot with colorbar
            ViewerREPL.select_variable(state, "v 5d_float")
            ViewerREPL.select_plot_type(state, "p heatmap")
            for f in (f1, f2, f3, f4, f5)
                output = f()
                for (i, kw) in enumerate(propertynames(state.controller.fd.cbar[]))
                    @test occursin(string(kw), output)
                    if i > 5  # Limit to first 5 to speed up tests
                        break
                    end
                end
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Range Keywords" begin
            # Arrange
            state = init_state()
            f1 = () -> ViewerREPL.get_range_kwargs(state, "kwargs")
            f2 = () -> ViewerREPL.get_kwargs_list(state, "kwargs range")
            f3 = () -> ViewerREPL.evaluate_command(state, "kwargs range")
            f4 = () -> ViewerREPL.get_kwargs_list(state, "kwargs")
            f5 = () -> ViewerREPL.evaluate_command(state, "kwargs")

            for f in (f1, f2, f3, f4, f5)
                # Act
                output = f()
                for (i, kw) in enumerate(propertynames(state.controller.fd.range_control[]))
                    @test occursin(string(kw), output)
                    if i > 5  # Limit to first 5 to speed up tests
                        break
                    end
                end
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Kwarg Value" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")
            ViewerREPL.select_plot_type(state, "p heatmap")
            ViewerREPL.apply_kwargs(state, "xlabel=\"Test X\", ylabel=\"Test Y\", colormap=:deep, titlesize=30")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            for f in (ViewerREPL.get_kwarg_value, ViewerREPL.evaluate_command)
                # Act & Assert: Valid key
                @test f(state, "get xlabel") == "xlabel => \"Test X\""
                @test f(state, "get ylabel") == "ylabel => \"Test Y\""
                @test f(state, "get colormap") == "colormap => :deep"
                @test f(state, "get titlesize") == "titlesize => 30.0"
                @test f(state, "get limits") == "limits => (nothing, nothing)"
                @test f(state, "get lon") == "lon => " * string(collect(Float64, 1:5))  

                # Act & Assert: Invalid key
                @test_warn "not found in any plot object" begin
                    @test f(state, "get invalid_key") == ""
                end

                # Act & Assert: Wrong Usage
                @test_warn "Usage:" begin
                    @test f(state, "get") == ""
                end
            end

            # Cleanup
            cleanup(state)
        end


        @testset "Apply Kwargs" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_plot_type(state, "p line")
            ax = state.controller.fd.ax[]
            plot_obj = state.controller.fd.plot_obj[]

            # Act: Apply via function
            output = ViewerREPL.apply_kwargs(state, "xlabel=\"Test X\", ylabel=\"Test Y\", color=:red")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert
            @test occursin("Current plot settings:", output)
            @test occursin("xlabel => \"Test X\"", output)
            @test occursin("ylabel => \"Test Y\"", output)
            @test occursin("color => :red", output)
            @test ax.xlabel[] == "Test X"
            @test ax.ylabel[] == "Test Y"

            # Act: Apply via evaluate_command
            output = ViewerREPL.evaluate_command(state, "linewidth=2")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert
            @test occursin("Current plot settings:", output)
            @test occursin("xlabel => \"Test X\"", output)
            @test occursin("ylabel => \"Test Y\"", output)
            @test occursin("color => :red", output)
            @test occursin("linewidth => 2", output)
            @test plot_obj.linewidth[] == 2

            # Cleanup
            cleanup(state)
        end

        @testset "Delete Kwarg" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_plot_type(state, "p line")
            ViewerREPL.apply_kwargs(state, "xlabel=\"Test X\", ylabel=\"Test Y\", color=:red, linewidth=2")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            # Act: Delete via function
            output = ViewerREPL.delete_kwarg(state, "del xlabel")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert
            @test occursin("Current plot settings:", output)
            @test !occursin("xlabel", output)
            @test occursin("ylabel => \"Test Y\"", output)
            @test occursin("color", output)
            @test occursin("linewidth", output)

            # Refresh the plot to ensure changes are applied
            ViewerREPL.evaluate_command(state, "refresh")
            ax = state.controller.fd.ax[]
            plot_obj = state.controller.fd.plot_obj[]

            @test ax.xlabel[] == "lon"  # Should be reset to default
            @test ax.ylabel[] == "Test Y"
            @test plot_obj.linewidth[] == 2.0

            # Act: Delete via evaluate_command
            output = ViewerREPL.evaluate_command(state, "del ylabel")
            # Wait for the tasks to complete
            [wait(t) for t in state.controller.fd.tasks[]]

            # Refresh the plot to ensure changes are applied
            ViewerREPL.evaluate_command(state, "refresh")
            ax = state.controller.fd.ax[]
            plot_obj = state.controller.fd.plot_obj[]

            # Assert
            @test occursin("Current plot settings:", output)
            @test !occursin("xlabel", output)
            @test !occursin("ylabel", output)
            @test ax.xlabel[] == "lon"  # Should be reset to default
            @test ax.ylabel[] == ""
            @test plot_obj.linewidth[] == 2.0

            # Cleanup
            cleanup(state)
        end

        @testset "Get Variable List" begin
            # Arrange
            state = init_state()

            # Act
            output = ViewerREPL.get_variable_list(state, "vars")

            # Assert
            @test occursin("Available variables:", output)
            for var in keys(VAR_DICT)
                @test occursin(var, output)
            end

            # Act via evaluate_command
            output = ViewerREPL.evaluate_command(state, "vars")

            # Assert
            @test occursin("Available variables:", output)
            for var in keys(VAR_DICT)
                @test occursin(var, output)
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Plot Types" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act
            output = ViewerREPL.get_plot_types(state, "plots")

            # Assert
            @test occursin("Available plot types:", output)
            for plot_type in keys(Plotting.PLOT_TYPES)
                @test occursin(plot_type, output)
            end

            # Act via evaluate_command
            output = ViewerREPL.evaluate_command(state, "plots")

            # Assert
            @test occursin("Available plot types:", output)
            for plot_type in keys(Plotting.PLOT_TYPES)
                @test occursin(plot_type, output)
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Var Info" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")
            ds = state.controller.dataset.ds

            # Act & Assert: via function
            @test ViewerREPL.get_var_info(state, "varinfo") == string(ds["5d_float"])
            @test ViewerREPL.get_var_info(state, "varinfo 2d_float") == string(ds["2d_float"])

            # Act & Assert: via evaluate_command
            @test ViewerREPL.evaluate_command(state, "varinfo") == string(ds["5d_float"])
            @test ViewerREPL.evaluate_command(state, "varinfo 2d_float") == string(ds["2d_float"])

            # Act & Assert: Invalid variable
            @test_warn "Variable 'invalid_var' not found." begin
                @test ViewerREPL.get_var_info(state, "varinfo invalid_var") == ""
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Dim List" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 3d_float")

            for func in (ViewerREPL.get_dim_list, ViewerREPL.evaluate_command)
                # Act
                output = func(state, "dims")

                # Assert
                @test occursin("List of Dimensions:", output)
                for dim in get_dims("3d_float")
                    @test occursin(dim, output)
                end
            end

            # Act via evaluate_command
            output = ViewerREPL.evaluate_command(state, "dims 2d_gap_inv")

            # Assert
            @test occursin("List of Dimensions:", output)
            for dim in get_dims("2d_gap_inv")
                @test occursin(dim, output)
            end

            # Act & Assert: Invalid variable
            @test_warn "Variable 'invalid_var' not found." begin
                @test ViewerREPL.evaluate_command(state, "dims invalid_var") == ""
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Plot Settings" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_plot_type(state, "p line")

            for func in (ViewerREPL.get_plot_settings, ViewerREPL.evaluate_command)
                # Arrange
                ViewerREPL.apply_kwargs(state, "xlabel=\"Test X\", ylabel=\"Test Y\", color=:red, linewidth=2")
                # Wait for the tasks to complete
                [wait(t) for t in state.controller.fd.tasks[]]

                # Act
                output = func(state, "conf")

                # Assert
                @test occursin("Current plot settings:", output)
                @test occursin("xlabel => \"Test X\"", output)
                @test occursin("ylabel => \"Test Y\"", output)
                @test occursin("color => :red", output)
                @test occursin("linewidth => 2", output)

                # Act: Reset settings
                ViewerREPL.reset_plot_settings(state, "")
                [wait(t) for t in state.controller.fd.tasks[]]
                output = func(state, "conf")

                # Assert: Should be empty now
                @test occursin("Current plot settings:", output)
                @test !occursin("xlabel", output)
                @test !occursin("ylabel", output)
                @test !occursin("color", output)
                @test !occursin("linewidth", output)
            end

            # Cleanup
            cleanup(state)
        end

        @testset "Get Help" begin
            # Arrange
            state = init_state()

            for func in (ViewerREPL.get_help, ViewerREPL.evaluate_command)
                # Act
                output = func(state, "help")

                # Assert
                @test occursin("Available commands:", output)
                for cmd in keys(ViewerREPL.commands)
                    @test occursin(cmd, output)
                end
                @test occursin("key=value", output)
                @test occursin("For a list of available keyword arguments, type", output)
            end

            # Cleanup
            cleanup(state)
        end

    end

end