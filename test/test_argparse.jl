using Test
using GLMakie
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
            @test controller.fd.plot_obj[] isa plot_class
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
            @test controller.ui.state.plot_kw[] == kwargs
        end
        if path != ""
            @test controller.ui.state.save_path[] == path
        end
        if saveoptions != ""
            @test controller.ui.main_menu.export_menu.options.stored_string[] == saveoptions
        end
        nothing
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
        end

        @testset "Variable Selection" begin
            controller = arange_controller("-v3d_float")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
            )
        end

        @testset "Axis Selection (1D)" begin
            controller = arange_controller("-v3d_float -xlat")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lat"],
            )
        end

        @testset "Axis Selection (2D)" begin
            controller = arange_controller("-v3d_float -xlon -ylat")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lon", "lat"],
            )
        end

        @testset "Axis Selection (3D)" begin
            controller = arange_controller("-v3d_float -xlon -ylat -ztime")
            assert_controller(controller;
                variable="3d_float",
                plot_type=NS,
                dims=["lon", "lat", "time"],
            )
        end

        @testset "Plot Type Selection" begin
            controller = arange_controller("-v5d_float -pheatmap")
            assert_controller(controller;
                variable="5d_float",
                plot_type="heatmap",
                plot_class=Heatmap,
                dims=["lon", "lat"],
            )
        end

        @testset "Dimension Indices" begin
            controller = arange_controller("-v5d_float -xlon -ylat --dims=\"float_dim=3, only_unit=2, only_long=1\"");
            assert_controller(controller;
                variable="5d_float",
                plot_type=NS,
                dims=["lon", "lat"],
                dim_idxs=Dict("float_dim" => 3, "only_unit" => 2, "only_long" => 1),
            )
        end

        @testset "Animation Dimension" begin
            controller = arange_controller("-v5d_float -xlon -ylat -afloat_dim");
            assert_controller(controller;
                variable="5d_float",
                plot_type=NS,
                dims=["lon", "lat"],
                play_dim="float_dim",
            )
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
            kwargs="colormap=:ice, xlabel=\"Longitude\", azimuth=30, elevation=20, limits=(1, 4, 2, 8, 1, 3)",
            path="",
            saveoptions="filename=\"my_volume.png\""
        )
    end


end