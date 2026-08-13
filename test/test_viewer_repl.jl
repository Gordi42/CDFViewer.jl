using Test

using GLMakie
using Makie
using Suppressor
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller
using CDFViewer.Parsing
using CDFViewer.Themes
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

        @testset "Select both vector components" begin
            # Arrange
            controller = Controller.ViewerController(
                make_vector_temp_dataset(), headless = true)
            state = ViewerREPL.REPLState(controller)
            ui_state = controller.ui.state

            # Act & Assert: one comma-separated token names both
            status = ViewerREPL.evaluate_command(state, "v uas,vas")
            @test occursin("Selected: uas", status)
            @test occursin("Selected: vas", status)
            @test ui_state.variable[] == "uas"
            @test ui_state.variable2[] == "vas"

            # Act & Assert: the partner is overridable on its own
            @test ViewerREPL.evaluate_command(state, "v uas,temp") ==
                "Selected: uas\nSelected: temp"
            @test ui_state.variable2[] == "temp"

            # Act & Assert: a partner over the wrong dimensions is refused
            @test_warn "Invalid selection:" begin
                ViewerREPL.evaluate_command(state, "v u,vmix")
            end
            @test ui_state.variable[] == "u"

            # Act & Assert: selecting a vector type guesses the partner
            ViewerREPL.evaluate_command(state, "x lon")
            ViewerREPL.evaluate_command(state, "y lat")
            ViewerREPL.evaluate_command(state, "v u")
            ViewerREPL.evaluate_command(state, "p quiver")
            @test ui_state.variable2[] == "v"
            @test Plotting.primary(controller.fd) isa Makie.Arrows2D

            # Act & Assert: an explicit partner survives a plot type
            # change, but not a change of the variable it belongs to
            ViewerREPL.evaluate_command(state, "v u,temp")
            @test ui_state.variable2[] == "temp"
            ViewerREPL.evaluate_command(state, "p streamplot")
            @test ui_state.variable2[] == "temp"
            ViewerREPL.evaluate_command(state, "v U10")
            @test ui_state.variable2[] == "V10"

            # Act & Assert: a variable with no partner in the file leaves
            # the second component empty instead of failing
            ViewerREPL.evaluate_command(state, "p quiver")
            ViewerREPL.evaluate_command(state, "v temp")
            @test ui_state.variable2[] == Constants.NOT_SELECTED_LABEL
            @test Plotting.primary(controller.fd) isa Makie.Arrows2D

            # Act & Assert: tab completion past the comma offers the
            # partners of the selected variable, not every variable
            ViewerREPL.evaluate_command(state, "v U10")
            word, cands = ViewerREPL.completion_candidates(state, "v U10,V")
            @test word == "V"
            @test "V10" in cands
            @test "U10" ∉ cands

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

        @testset "Play and Stop" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")
            toggle = state.controller.ui.main_menu.playback_menu.toggle

            # Act & Assert: play starts, and stays started
            @test ViewerREPL.start_play(state, "play") == "Playing."
            @test toggle.active[] == true
            @test ViewerREPL.start_play(state, "play") == "Already playing."
            @test toggle.active[] == true

            # Act & Assert: only stop stops
            @test ViewerREPL.stop_play(state, "stop") == "Stopped."
            @test toggle.active[] == false
            @test ViewerREPL.stop_play(state, "stop") == "Not playing."
            @test toggle.active[] == false

            # Act & Assert: Set dimension while starting play
            @test ViewerREPL.start_play(state, "play float_dim") == "Playing."
            @test toggle.active[] == true
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
                for (i, kw) in enumerate(propertynames(Plotting.primary(state.controller.fd)))
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
            plot_obj = Plotting.primary(state.controller.fd)

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

        @testset "Apply Expression Kwargs" begin
            # a value like `Makie.Symlog10(1e-2)` has no text form that
            # reads back. It used to be serialised into the menu's keyword
            # box and parsed again, which lost it -- and the
            # all-or-nothing revert took the keyword beside it down too.
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 2d_float")
            ViewerREPL.select_x_axis(state, "x lon")
            ViewerREPL.select_y_axis(state, "y lat")
            ViewerREPL.select_plot_type(state, "p heatmap")

            # Act: both keywords on one line
            ViewerREPL.evaluate_command(
                state, "colorscale=Makie.Symlog10(1e-2), colormap=:plasma")
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert
            plot_obj = Plotting.primary(state.controller.fd)
            @test plot_obj.colorscale[] isa Makie.ReversibleScale
            @test plot_obj.colormap[] == :plasma

            # Act: and a third keyword after them, which reads the store
            # back and would carry a mangled value along
            ViewerREPL.evaluate_command(state, "title=\"Symlog\"")
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert: the first two are still on
            @test plot_obj.colorscale[] isa Makie.ReversibleScale
            @test plot_obj.colormap[] == :plasma
            @test state.controller.fd.title_text[] == "Symlog"

            # Cleanup
            cleanup(state)
        end

        @testset "Apply Expression Kwargs One at a Time" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 2d_float")
            ViewerREPL.select_x_axis(state, "x lon")
            ViewerREPL.select_y_axis(state, "y lat")
            ViewerREPL.select_plot_type(state, "p heatmap")

            # Act: one line each
            ViewerREPL.evaluate_command(state, "colorscale=Makie.Symlog10(1e-2)")
            [wait(t) for t in state.controller.fd.tasks[]]
            ViewerREPL.evaluate_command(state, "colormap=:plasma")
            [wait(t) for t in state.controller.fd.tasks[]]

            # Assert
            plot_obj = Plotting.primary(state.controller.fd)
            @test plot_obj.colorscale[] isa Makie.ReversibleScale
            @test plot_obj.colormap[] == :plasma
            # and the store holds the object, not a rendering of it
            @test state.controller.ui.state.kwargs[][:colorscale] isa Makie.ReversibleScale

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
            plot_obj = Plotting.primary(state.controller.fd)

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
            plot_obj = Plotting.primary(state.controller.fd)

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

        @testset "Completion Candidates" begin
            # Arrange
            state = init_state()
            ViewerREPL.select_variable(state, "v 5d_float")

            # Act & Assert: first word completes commands, exit and kwarg= entries
            word, cands = ViewerREPL.completion_candidates(state, "")
            @test word == ""
            for cmd in keys(ViewerREPL.commands)
                @test cmd in cands
            end
            @test "exit" in cands
            @test any(endswith("="), cands)  # top-level key=value syntax

            word, cands = ViewerREPL.completion_candidates(state, "he")
            @test word == "he"
            @test "help" in cands

            # Act & Assert: variable name completion
            word, cands = ViewerREPL.completion_candidates(state, "v ")
            @test word == ""
            @test "5d_float" in cands
            word, cands = ViewerREPL.completion_candidates(state, "v 5d")
            @test word == "5d"
            @test "5d_float" in cands
            word, cands = ViewerREPL.completion_candidates(state, "varinfo 2d")
            @test "2d_float" in cands

            # Act & Assert: plot type completion
            word, cands = ViewerREPL.completion_candidates(state, "p hea")
            @test word == "hea"
            @test "heatmap" in cands

            # Act & Assert: axis completion
            word, cands = ViewerREPL.completion_candidates(state, "x lo")
            @test "lon" in cands
            word, cands = ViewerREPL.completion_candidates(state, "y ")
            @test "lat" in cands

            # Act & Assert: dimension completion for isel/sel
            word, cands = ViewerREPL.completion_candidates(state, "isel ")
            @test "float_dim" in cands
            word, cands = ViewerREPL.completion_candidates(state, "sel flo")
            @test word == "flo"
            @test "float_dim" in cands

            # Act & Assert: kwargs categories
            word, cands = ViewerREPL.completion_candidates(state, "kwargs fi")
            @test word == "fi"
            @test cands == ["axis", "colorbar", "figure", "plot", "range"]

            # Act & Assert: kwarg names for get/del
            word, cands = ViewerREPL.completion_candidates(state, "get ")
            @test !isempty(cands)
            @test !any(endswith("="), cands)

            # Act & Assert: continuation of key=value lines completes kwarg names
            word, cands = ViewerREPL.completion_candidates(state, "xlabel=\"a\", yla")
            @test word == "yla"
            @test all(endswith("="), cands)

            # Act & Assert: unknown command yields no candidates
            word, cands = ViewerREPL.completion_candidates(state, "unknowncmd ")
            @test isempty(cands)

            # Cleanup
            cleanup(state)
        end

        @testset "Overview command" begin
            state = init_state()
            # Prints directly (returns "") so the table keeps its alignment.
            local out
            @test (out = @capture_out ViewerREPL.show_overview(state, "overview")) isa String
            @test occursin("Variable", out)
            @test occursin("Coordinates:", out)
            @test occursin("5d_float", out)
            @test ViewerREPL.evaluate_command(state, "overview") == ""
            cleanup(state)
        end

        @testset "complete_line contract" begin
            # Regression: edit_move_right (right-arrow at end of line) calls
            # complete_line directly and indexes `completions[1].completion`
            # and `reg.second`/`reg.first`. Returning the old
            # (Vector{String}, String, Bool) form made it crash with
            # `type String has no field second`. complete_line must hand back
            # the normalised (Vector{NamedCompletion}, Region, Bool) form.
            state = init_state()
            LE = ViewerREPL.LineEdit
            prov = ViewerREPL.CDFCompletionProvider(state)
            prompt = LE.Prompt("CDFViewer> "; complete = prov)
            term = ViewerREPL.REPL.Terminals.TTYTerminal(
                "dumb", stdin, stdout, stderr)
            ps = LE.init_state(term, prompt)
            write(LE.buffer(ps), "hel")
            seekend(LE.buffer(ps))

            completions, reg, should_complete = LE.complete_line(prov, ps, Main)

            @test reg isa LE.Region              # Pair{Int,Int}, has .first/.second
            @test reg.second - reg.first == 3    # length of the word "hel"
            @test should_complete
            @test completions isa Vector{LE.NamedCompletion}
            @test length(completions) == 1
            @test completions[1].completion == "help"  # accessed by edit_move_right

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

        @testset "History Navigation" begin
            # Regression: the history provider used to be created with the
            # constructor default cur_idx == 0. The first up/down arrow then
            # tripped `@assert 1 <= hist.cur_idx <= max_idx` inside
            # REPL.history_move (and, later, transition(::Nothing)). The cursor
            # must start one past the last entry so navigation is safe.
            new_prompt() = ViewerREPL.LineEdit.Prompt("CDFViewer> ")

            mktempdir() do dir
                # Empty history (the reported "fresh environment" case)
                empty_hist = joinpath(dir, "empty_history")
                withenv("CDFVIEWER_HISTORY" => empty_hist) do
                    prompt = new_prompt()
                    hp = ViewerREPL.setup_history!(prompt)
                    @test isempty(hp.history)
                    @test hp.cur_idx == length(hp.history) + 1
                    @test 1 <= hp.cur_idx <= length(hp.history) + 1
                    @test prompt.hist === hp
                    close(hp.history_file)
                end

                # Pre-populated history file
                pop_hist = joinpath(dir, "populated_history")
                write(pop_hist,
                    "# time: 2024-01-01 00:00:00 UTC\n# mode: cdfviewer\n\thelp\n" *
                    "# time: 2024-01-01 00:00:01 UTC\n# mode: cdfviewer\n\tvars\n")
                withenv("CDFVIEWER_HISTORY" => pop_hist) do
                    prompt = new_prompt()
                    hp = ViewerREPL.setup_history!(prompt)
                    @test hp.history == ["help", "vars"]
                    @test hp.cur_idx == length(hp.history) + 1
                    @test 1 <= hp.cur_idx <= length(hp.history) + 1
                    close(hp.history_file)
                end
            end
        end

    end

    @testset "Overlaid layers" begin

        "A `u` heatmap on lon/lat, ready to be overlaid."
        function init_overlay_state()
            controller = Controller.ViewerController(
                make_vector_temp_dataset(), headless = true)
            state = ViewerREPL.REPLState(controller)
            for cmd in ("v u", "x lon", "y lat", "p heatmap")
                ViewerREPL.evaluate_command(state, cmd)
            end
            state
        end

        @testset "Recognising the command word" begin
            parse = ViewerREPL.layer_command
            @test parse("over") == (2, "")
            @test parse("over2") == (3, "")
            @test parse("over.v") == (2, "v")
            @test parse("over2.p") == (3, "p")
            @test parse("base") == (1, "")
            @test parse("base.p") == (1, "p")
            # a keyword line is not a layer command: its first token
            # carries the `=` and falls through to the kwargs branch
            @test parse("over.colormap=:reds") === nothing
            @test parse("over.levels=-30:5:30") === nothing
            @test parse("colormap") === nothing
            @test parse("over0") === nothing
        end

        @testset "Adding, retyping and removing" begin
            state = init_overlay_state()
            fd = state.controller.fd

            status = ViewerREPL.evaluate_command(state, "over temp")
            @test occursin("over: temp", status)
            @test Plotting.layer_count(fd) == 2
            @test Plotting.layer_plot(fd, 2).type == "contour"

            # the spelled-out form does the same
            ViewerREPL.evaluate_command(state, "over.v uodd")
            @test Plotting.layer_variables(fd, 2) == ["uodd"]

            # a plot type of its own
            ViewerREPL.evaluate_command(state, "over.p contourf")
            @test Plotting.layer_plot(fd, 2).type == "contourf"

            # a third layer, naming both components of a vector plot
            ViewerREPL.evaluate_command(state, "over2 u,v")
            @test Plotting.layer_count(fd) == 3
            # two names pick a vector type without being told
            @test Plotting.layer_plot(fd, 3).type == "quiver"
            @test Plotting.layer_variables(fd, 3) == ["u", "v"]

            # no argument reports what a layer draws
            @test occursin("uodd", ViewerREPL.evaluate_command(state, "over"))
            @test occursin("not set",
                           ViewerREPL.evaluate_command(state, "over3"))

            # and `off` takes one away
            @test occursin("Removed layer over2",
                           ViewerREPL.evaluate_command(state, "over2 off"))
            @test Plotting.layer_count(fd) == 2
            ViewerREPL.evaluate_command(state, "over off")
            @test Plotting.layer_count(fd) == 1
            cleanup(state)
        end

        @testset "Keywords address a layer" begin
            state = init_overlay_state()
            fd = state.controller.fd
            ViewerREPL.evaluate_command(state, "over temp")

            # a prefixed keyword is not a command; it goes through the
            # `key=value` branch untouched. The pin turns the count into
            # concrete boundaries, so count the lines rather than read it.
            level_count(plot) = plot.levels[] isa Integer ?
                plot.levels[] : length(plot.levels[])
            ViewerREPL.evaluate_command(state, "over.levels=4")
            @test level_count(fd.layers[2].plot_obj[]) == 4
            @test haskey(state.controller.ui.state.kwargs[],
                         Symbol("over.levels"))

            ViewerREPL.evaluate_command(state, "base.colormap=:thermal")
            @test Plotting.primary(fd).colormap[] == :thermal
            @test fd.layers[2].plot_obj[].colormap[] != :thermal

            # `get` on a bare name reports the base
            @test occursin("thermal",
                           ViewerREPL.evaluate_command(state, "get colormap"))
            @test occursin("over.levels =>",
                           ViewerREPL.evaluate_command(state, "get over.levels"))

            # `conf` prints the keys as written, `del` takes them as written
            @test occursin("over.levels => 4",
                           ViewerREPL.evaluate_command(state, "conf"))
            ViewerREPL.evaluate_command(state, "del over.levels")
            @test !haskey(state.controller.ui.state.kwargs[],
                          Symbol("over.levels"))
            cleanup(state)
        end

        @testset "Keyword listings and completion" begin
            state = init_overlay_state()
            fd = state.controller.fd

            # with one layer the plot keywords are bare, as they always were
            names = ViewerREPL.plot_kwarg_names(fd)
            @test "colormap" in names
            @test !any(startswith("over."), names)
            @test !any(startswith("over."), ViewerREPL.get_kwarg_names(state))

            ViewerREPL.evaluate_command(state, "over temp")
            names = ViewerREPL.plot_kwarg_names(fd)
            @test "colormap" in names
            @test "over.levels" in names
            @test occursin("over.levels",
                           ViewerREPL.get_plot_kwargs(state, "kwargs plot"))

            # completion offers the layer words, and `off` only for a layer
            # that is there to remove
            _, cands = ViewerREPL.completion_candidates(state, "ove")
            @test "over" in cands && "over.p" in cands && "over2" in cands
            @test "over3" ∉ cands
            _, cands = ViewerREPL.completion_candidates(state, "over ")
            @test "temp" in cands && "off" in cands
            _, cands = ViewerREPL.completion_candidates(state, "over2 ")
            @test "off" ∉ cands
            _, cands = ViewerREPL.completion_candidates(state, "over.p ")
            @test "contour" in cands
            @test "surface" ∉ cands
            # and the prefixed keyword names only exist once a layer does
            @test "over.levels=" in
                ViewerREPL.completion_candidates(state, "over.l")[2]
            cleanup(state)
        end
    end

    @testset "Theme" begin
        # the switch installs a theme globally; put the default back
        function with_default_theme(f::Function)
            try
                f()
            finally
                Themes.activate!(Themes.DEFAULT_THEME)
            end
        end

        @testset "Reporting the current theme" begin
            with_default_theme() do
                state = init_state()
                output = ViewerREPL.evaluate_command(state, "theme")
                @test occursin("Theme: " * Themes.DEFAULT_THEME, output)
                for name in Themes.theme_names()
                    @test occursin(name, output)
                end
                cleanup(state)
            end
        end

        @testset "Switching the theme" begin
            with_default_theme() do
                state = init_state()
                ViewerREPL.evaluate_command(state, "v 2d_float")
                ViewerREPL.evaluate_command(state, "p heatmap")
                figure = state.controller.fd.fig

                @test ViewerREPL.evaluate_command(state, "theme dark") ==
                    "Theme: dark"

                # the REPL holds the controller, and the controller is the
                # thing that was rebuilt into -- so the prompt keeps working
                @test state.controller.fd.fig !== figure
                @test Controller.get_theme(state.controller) == "dark"
                @test ViewerREPL.evaluate_command(state, "v 3d_float") ==
                    "Selected: 3d_float"
                cleanup(state)
            end
        end

        @testset "Refusing a name at the prompt" begin
            with_default_theme() do
                state = init_state()
                output = ViewerREPL.evaluate_command(state, "theme solarized")
                @test occursin("Unknown theme 'solarized'", output)
                @test Controller.get_theme(state.controller) ==
                    Themes.DEFAULT_THEME
                cleanup(state)
            end
        end

        @testset "Completion offers the theme names" begin
            with_default_theme() do
                state = init_state()
                word, cands = ViewerREPL.completion_candidates(state, "theme d")
                @test word == "d"
                @test "dark" in cands
                _, cands = ViewerREPL.completion_candidates(state, "theme ")
                @test sort(Themes.theme_names()) == cands
                cleanup(state)
            end
        end
    end

end