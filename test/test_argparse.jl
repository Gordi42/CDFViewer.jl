using Test
using GLMakie
using GeoMakie
using Suppressor
using ArgParse
using CDFViewer
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller

NS = Constants.NOT_SELECTED_LABEL

@testset "Command Line Parsing" begin

    function get_args(fname::String="", arg_string::String="")::Dict{String,Any}
        fullargs = fname * " " * arg_string
        fullargs = Base.shell_split(strip(fullargs))
        parse_args(fullargs, CDFViewer.get_arg_parser())
    end

    function arange_controller(arg_string::String)::Controller.ViewerController
        fname = init_temp_dataset()
        args = get_args(fname, arg_string)
        dataset = Data.CDFDataset(args["files"])
        Controller.ViewerController(dataset, headless=true, parsed_args=args)
    end

    function assert_controller(controller::Controller.ViewerController;
        variable::Union{String, Nothing}=nothing,
        plot_type::String="",
        plot_class::Union{Type, Nothing}=nothing,
        dims::Vector{String}=String[],
        play_dim::Union{String, Nothing}=nothing,
        dim_idxs::Dict{String,Int}=Dict{String,Int}(),
        kwargs::String="",
        path::String="",
        saveoptions::String=""
    )::Nothing
        if variable !== nothing
            @test controller.ui.state.variable[] == variable
        end
        if plot_type != ""
            @test controller.ui.state.plot_type_name[] == plot_type
        end
        if plot_class !== nothing
            @test Plotting.primary(controller.fd) isa plot_class
        end
        if !isempty(dims)
            state = controller.ui.state
            @test state.x_name[] == (length(dims) ≥ 1 ? dims[1] : NS)
            @test state.y_name[] == (length(dims) ≥ 2 ? dims[2] : NS)
            @test state.z_name[] == (length(dims) == 3 ? dims[3] : NS)
        end
        if play_dim !== nothing
            play_menu = controller.ui.main_menu.playback_menu.var
            @test play_menu.selection[] == play_dim
        end
        for (dim, idx) in dim_idxs
            sliders = controller.ui.main_menu.coord_sliders.sliders
            @test sliders[dim].value[] == idx
        end
        if kwargs != ""
            @test controller.ui.main_menu.plot_menu.plot_kw.stored_string[] == kwargs
        end
        if path != ""
            @test controller.ui.state.save_path[] == path
        end
        if saveoptions != ""
            @test controller.ui.main_menu.export_menu.options.stored_string[] == saveoptions
        end
        nothing
    end

    function cleanup(controller::Controller.ViewerController)
        GLMakie.closeall()
        close(controller.dataset.ds)
    end

    @testset "Argument Parsing" begin

        @testset "Default" begin
            args = get_args("file.nc")
            @test args["files"] == ["file.nc"]
            @test args["var"] == ""
            @test args["x-axis"] == ""
            @test args["y-axis"] == ""
            @test args["z-axis"] == ""
            @test args["plot_type"] == ""
            @test args["kwargs"] == ""
            @test args["dims"] == ""
            @test args["ani-dim"] == ""
            @test args["saveoptions"] == ""
            @test args["savefig"] == false
            @test args["record"] == false
            @test args["menu"] == false
            @test args["use-local"] == false
            @test args["no-summary"] == false
        end

        @testset "No summary" begin
            args = get_args("file.nc", "--no-summary")
            @test args["no-summary"] == true
        end

        @testset "Files" begin
            args = get_args("file1.nc file2.nc")
            @test args["files"] == ["file1.nc", "file2.nc"]
        end

        @testset "Variable" begin
            args = get_args("file.nc", "--var=temperature")
            @test args["var"] == "temperature"
            args = get_args("file.nc", "-vtemperature")
            @test args["var"] == "temperature"
        end

        @testset "Axes" begin
            args = get_args("file.nc", "--x-axis=lon --y-axis=lat --z-axis=level")
            @test args["x-axis"] == "lon"
            @test args["y-axis"] == "lat"
            @test args["z-axis"] == "level"
            args = get_args("file.nc", "-xlon -ylat -zlevel")
            @test args["x-axis"] == "lon"
            @test args["y-axis"] == "lat"
            @test args["z-axis"] == "level"
        end

        @testset "Plot Type" begin
            args = get_args("file.nc", "--plot_type=contour")
            @test args["plot_type"] == "contour"
            args = get_args("file.nc", "-pcontour")
            @test args["plot_type"] == "contour"
        end
        
        @testset "Keyword Arguments" begin
            args = get_args("file.nc", "--kwargs='color=:red, linewidth=2, title=\"My Plot\"'")
            @test args["kwargs"] == "color=:red, linewidth=2, title=\"My Plot\""
        end

        @testset "Dimensions" begin
            args = get_args("file.nc", "--dims=\"time=5, lat=10\"")
            @test args["dims"] == "time=5, lat=10"
        end

        @testset "Animation Dimension" begin
            args = get_args("file.nc", "--ani-dim=time")
            @test args["ani-dim"] == "time"
            args = get_args("file.nc", "-atime")
            @test args["ani-dim"] == "time"
        end

        @testset "Save Options" begin
            args = get_args("file.nc", "--saveoptions=\"dpi=300, quality=95\"")
            @test args["saveoptions"] == "dpi=300, quality=95"
        end

        @testset "Flags" begin
            args = get_args("file.nc", "--savefig --record --menu --use-local")
            @test args["savefig"] == true
            @test args["record"] == true
            @test args["menu"] == true
            @test args["use-local"] == true
        end

        @testset "Combined Arguments" begin
            args = get_args("file.nc", "--var=temperature -xlon -ylat -pcontour --dims=\"time=5\" --ani-dim=time --savefig --use-local")
            @test args["files"] == ["file.nc"]
            @test args["var"] == "temperature"
            @test args["x-axis"] == "lon"
            @test args["y-axis"] == "lat"
            @test args["z-axis"] == ""
            @test args["plot_type"] == "contour"
            @test args["kwargs"] == ""
            @test args["dims"] == "time=5"
            @test args["ani-dim"] == "time"
            @test args["saveoptions"] == ""
            @test args["savefig"] == true
            @test args["record"] == false
            @test args["menu"] == false
            @test args["use-local"] == true
        end
    end

    @testset "Controller Initialization" begin

        @testset "Default Initialization" begin
            controller = arange_controller("")
            assert_controller(controller;
                variable="1d_float",
                plot_type=NS,
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Variable Selection" begin
            controller = arange_controller("-v3d_float")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Axis Selection (1D)" begin
            controller = arange_controller("-v3d_float -xlat")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lat"],
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Axis Selection (2D)" begin
            controller = arange_controller("-v3d_float -xlon -ylat")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lon", "lat"],
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Axis Selection (3D)" begin
            controller = arange_controller("-v3d_float -xlon -ylat -ztime")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lon", "lat", "time"],
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Plot Type Selection" begin
            controller = arange_controller("-v5d_float -pheatmap")
            assert_controller(controller;
                variable="5d_float",
                plot_type="heatmap",
                plot_class=Heatmap,
                dims=["lon", "lat"],
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Dimension Indices" begin
            controller = arange_controller("-v5d_float -xlon -ylat --dims=\"float_dim=3, only_unit=2, only_long=1\"");
            assert_controller(controller;
                variable="5d_float",
                plot_type=NS,
                dims=["lon", "lat"],
                dim_idxs=Dict("float_dim" => 3, "only_unit" => 2, "only_long" => 1),
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Animation Dimension" begin
            controller = arange_controller("-v5d_float -xlon -ylat -afloat_dim");
            assert_controller(controller;
                variable="5d_float",
                plot_type=NS,
                dims=["lon", "lat"],
                play_dim="float_dim",
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Keyword Arguments" begin
            controller = arange_controller("-v3d_float -xlon -ylat -pcontour --kwargs=\"labels=true, linewidth=20\"");
            assert_controller(controller;
                variable="3d_float",
                plot_type="contour",
                plot_class=Contour,
                dims=["lon", "lat"],
                kwargs="labels=true, linewidth=20",
            )

            # Cleanup
            cleanup(controller)
        end

        @testset "Save Options" begin
            controller = arange_controller("-v3d_float -xlon -ylat -pcontour --saveoptions=\"filename=my_file.png\"");
            assert_controller(controller;
                variable="3d_float",
                plot_type="contour",
                plot_class=Contour,
                dims=["lon", "lat"],
                saveoptions="filename=my_file.png",
            )

            # Cleanup
            cleanup(controller)
        end

    end

    @testset "Complex Arg Parse Case" begin
        # Arrange
        controller = arange_controller("-v5d_float -xlon -ylat -zfloat_dim -pvolume --kwargs='colormap=:ice, xlabel=\"Longitude\"'")
        main_menu = controller.ui.main_menu
        playback = main_menu.playback_menu
        sliders = main_menu.coord_sliders.sliders
        exportmenu = main_menu.export_menu
        # change the values
        playback.var.i_selected[] = findfirst(==("only_unit"), playback.var.options[])
        sliders["only_unit"].value[] = 2
        sliders["only_long"].value[] = 3
        exportmenu.options.stored_string[] = "filename=\"my_volume.png\""
        # change the limits
        controller.fd.ax[].limits = (1, 4, 2, 8, 1, 3)
        controller.fd.ax[].azimuth = 30
        controller.fd.ax[].elevation = 20

        # Act
        exp_str = Controller.get_export_string(controller)
        controller2 = arange_controller(exp_str)

        # Assert
        assert_controller(controller2;
            variable="5d_float",
            plot_type="volume",
            plot_class=Volume,
            dims=["lon", "lat", "float_dim"],
            play_dim="only_unit",
            dim_idxs=Dict("only_unit" => 2, "only_long" => 3),
            kwargs="colormap=:ice, xlabel=\"Longitude\", limits=(1.0, 4.0, 2.0, 8.0, 1.0, 3.0), azimuth=30.0, elevation=20.0",
            path="",
            saveoptions="filename=\"my_volume.png\""
        )

        # Cleanup
        cleanup(controller)
    end

    @testset "Geographic Round Trip" begin
        # a map holds its extent in projected metres while it reads its
        # `limits` keyword as lon/lat. Exporting the metres wrote a
        # keyword nothing could apply: the failure reverted the whole
        # batch and left the colorbar's range filed under `limits`.
        projections = [("default", ""), ("mollweide", ", proj=\"+proj=moll\"")]
        for (name, extra) in projections, zoomed in (false, true)
            @testset "$name projection, zoomed = $zoomed" begin
                # Arrange
                controller = arange_controller(
                    "-v2d_float -xlon -ylat -pheatmap " *
                    "--kwargs='geographic=true$extra'")
                ax = controller.fd.ax[]
                @test ax isa GeoAxis
                if zoomed
                    rect = ax.finallimits[]
                    ax.targetlimits[] = typeof(rect)(
                        rect.origin .+ 0.2 .* rect.widths, 0.5 .* rect.widths)
                end
                before = ax.finallimits[]

                # Act
                local exp_str
                err = @capture_err begin
                    exp_str = Controller.get_export_string(controller)
                end

                # Assert: it applied cleanly, so nothing was taken back
                @test !occursin("reverting", err)
                @test !occursin("Error setting property", err)
                # what is exported is the axis' four corners in degrees,
                # not the colorbar's two-element range
                limits = controller.ui.state.kwargs[][:limits]
                span = maximum(limits) - minimum(limits)
                @test length(limits) == 4
                @test all(l -> abs(l) ≤ 360, limits)
                # applying them moved nothing: reading the axis again
                # gives the same extent back, so a second export does
                # not walk the view outward one edge at a time
                @test all(isapprox.(limits, Plotting.get_limit_string(ax),
                                    atol = 1e-4 * span))

                # Assert: the exported command draws the same map
                controller2 = arange_controller(exp_str)
                @test controller2.fd.ax[] isa GeoAxis
                after = controller2.fd.ax[].finallimits[]
                tol = 1e-3 * maximum(abs, before.widths)
                @test all(isapprox.(Tuple(before.origin), Tuple(after.origin),
                                    atol = tol))
                @test all(isapprox.(Tuple(before.widths), Tuple(after.widths),
                                    atol = tol))
                # and exporting that again asks for the same view. Not
                # for the same digits: GeoMakie measures a lon/lat
                # rectangle by sampling 21 parallels, so a limit lands
                # within a ten-thousandth of the span of where it began
                Controller.get_export_string(controller2)
                @test all(isapprox.(controller2.ui.state.kwargs[][:limits],
                                    limits, atol = 1e-3 * span))

                # Cleanup
                cleanup(controller)
                cleanup(controller2)
            end
        end
    end

    @testset "Overlaid layers" begin
        @testset "Repeated --over is matched by position" begin
            args = get_args("f.nc", "--over=a --over-plot=contour --over=b,c")
            @test args["over"] == ["a", "b,c"]
            @test args["over-plot"] == ["contour"]
            # nothing given is an empty list, not a leftover from before
            @test get_args("f.nc")["over"] == String[]
            @test get_args("f.nc")["over-plot"] == String[]
        end

        @testset "Layers are built from the command line" begin
            controller = arange_controller(
                "-v 2d_float -x lon -y lat -p heatmap " *
                "--over=int_var --over-plot=contourf")
            @test Plotting.layer_count(controller.fd) == 2
            @test Plotting.layer_variables(controller.fd, 2) == ["int_var"]
            @test Plotting.layer_plot(controller.fd, 2).type == "contourf"
            # without a --over-plot the layer takes the default type
            cleanup(controller)

            controller = arange_controller(
                "-v 2d_float -x lon -y lat -p heatmap --over=int_var")
            @test Plotting.layer_plot(controller.fd, 2).type == "contour"
            cleanup(controller)
        end

        @testset "Prefixed keywords find their layer" begin
            # the layers must exist before the keyword textbox is written,
            # or a prefixed keyword warns about a layer that is not there
            slot = Ref{Any}(nothing)
            output = @capture_err begin
                slot[] = arange_controller(
                    "-v 2d_float -x lon -y lat -p heatmap " *
                    "--over=int_var --over-plot=contour " *
                    "--kwargs='over.levels=7, colormap=:ice'")
            end
            controller = slot[]
            @test !occursin("not found in any plot object", output)
            @test Plotting.primary(controller.fd).colormap[] == :ice
            @test controller.fd.layers[2].plot_obj[].levels[] == 7
            cleanup(controller)
        end

        @testset "Export reproduces the layers" begin
            controller = arange_controller(
                "-v 2d_float -x lon -y lat -p heatmap " *
                "--over=int_var --over-plot=contourf")
            exp_str = Controller.get_export_string(controller)
            @test occursin("--over=int_var", exp_str)
            @test occursin("--over-plot=contourf", exp_str)

            controller2 = arange_controller(exp_str)
            @test Plotting.layer_count(controller2.fd) == 2
            @test Plotting.layer_variables(controller2.fd, 2) == ["int_var"]
            @test Plotting.layer_plot(controller2.fd, 2).type == "contourf"
            # the round trip is a fixed point
            @test Controller.get_export_string(controller2) == exp_str

            cleanup(controller)
            cleanup(controller2)
        end
    end

end