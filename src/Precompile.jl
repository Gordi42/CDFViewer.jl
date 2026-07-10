# Precompile workload
#
# Exercises the app's interactive surface (all plot types, sliders, kwargs,
# saving, recording, REPL commands) so the compiled code is cached in the
# package image. This is what makes startup fast and, more importantly,
# removes the first-click compilation lag on every button and command.
#
# The same workload is reused by the sysimage build (precompile_script.jl).

using PrecompileTools
using Logging: NullLogger, with_logger
using NCDatasets: NCDataset, defVar

function create_workload_file()::String
    file = tempname() * ".nc"
    nlon, nlat, nlev, ntime, ncells = 12, 10, 4, 4, 80

    NCDataset(file, "c") do ds
        defVar(ds, "lon", collect(range(-180.0, 180.0, nlon)), ("lon",), attrib = Dict(
            "standard_name" => "longitude", "units" => "degrees_east"))
        defVar(ds, "lat", collect(range(-80.0, 80.0, nlat)), ("lat",), attrib = Dict(
            "standard_name" => "latitude", "units" => "degrees_north"))
        defVar(ds, "lev", collect(1.0:nlev), ("lev",), attrib = Dict("units" => "m"))
        defVar(ds, "time", collect(1:ntime), ("time",), attrib = Dict(
            "units" => "days since 2000-01-01 00:00:00"))

        defVar(ds, "var1d", rand(nlon), ("lon",), attrib = Dict("units" => "K"))
        defVar(ds, "var4d", rand(nlon, nlat, nlev, ntime), ("lon", "lat", "lev", "time"),
            attrib = Dict("units" => "K", "long_name" => "Workload variable"))

        # Unstructured part (ICON-style: paired coordinates on one dimension)
        defVar(ds, "clon", rand(ncells) .* 360.0 .- 180.0, ("ncells",), attrib = Dict(
            "standard_name" => "longitude", "units" => "degrees_east"))
        defVar(ds, "clat", rand(ncells) .* 160.0 .- 80.0, ("ncells",), attrib = Dict(
            "standard_name" => "latitude", "units" => "degrees_north"))
        defVar(ds, "var_unstructured", rand(ncells, ntime), ("ncells", "time"),
            attrib = Dict("units" => "K", "coordinates" => "clat clon"))
    end

    file
end

function exercise_repl_commands!(state::ViewerREPL.REPLState)::Nothing
    wait_tasks() = foreach(wait, state.controller.fd.tasks[])

    # Structured variable: set axes, then cycle through every plot type
    ViewerREPL.evaluate_command(state, "v var4d")
    ViewerREPL.evaluate_command(state, "x lon")
    ViewerREPL.evaluate_command(state, "y lat")
    ViewerREPL.evaluate_command(state, "z lev")
    for plot_type in keys(Plotting.PLOT_TYPES)
        plot_type == Constants.NOT_SELECTED_LABEL && continue
        ViewerREPL.evaluate_command(state, "p $plot_type")
        wait_tasks()
    end

    # 1D plots
    ViewerREPL.evaluate_command(state, "v var1d")
    for plot_type in ("line", "scatter")
        ViewerREPL.evaluate_command(state, "p $plot_type")
        wait_tasks()
    end

    # Unstructured variable (nearest-neighbor interpolation path)
    ViewerREPL.evaluate_command(state, "v var_unstructured")
    ViewerREPL.evaluate_command(state, "x clon")
    ViewerREPL.evaluate_command(state, "y clat")
    ViewerREPL.evaluate_command(state, "p heatmap")
    wait_tasks()

    # Sliders, playback, kwargs, info commands
    ViewerREPL.evaluate_command(state, "v var4d")
    ViewerREPL.evaluate_command(state, "p heatmap")
    wait_tasks()
    ViewerREPL.evaluate_command(state, "isel time 2")
    ViewerREPL.evaluate_command(state, "sel lev 2.0")
    ViewerREPL.evaluate_command(state, "pdim time")
    ViewerREPL.evaluate_command(state, "play")
    ViewerREPL.evaluate_command(state, "play")
    ViewerREPL.evaluate_command(state, "speed 2.0")
    ViewerREPL.evaluate_command(state, "colormap=:viridis, title=\"workload\"")
    wait_tasks()
    ViewerREPL.evaluate_command(state, "get colormap")
    ViewerREPL.evaluate_command(state, "del title")
    wait_tasks()
    for cmd in ("help", "vars", "plots", "dims", "varinfo", "conf", "kwargs", "refresh", "reset")
        ViewerREPL.evaluate_command(state, cmd)
        wait_tasks()
    end
    # Compile the overview directly (the `overview` command only wraps this and
    # prints, which we do not want cluttering precompilation output).
    Data.overview_string(state.controller.dataset)

    # Tab completion
    for prefix in ("", "he", "v ", "p hea", "isel ", "kwargs fi", "xlabel=\"a\", yla")
        ViewerREPL.completion_candidates(state, prefix)
    end

    # Export paths: figure, movie, command string
    ViewerREPL.evaluate_command(state, "savefig filename=$(tempname()).png")
    ViewerREPL.evaluate_command(state, "record filename=$(tempname()).mkv, framerate=10")
    ViewerREPL.evaluate_command(state, "export")
    nothing
end

function create_workload_grid_pair()::Tuple{String, String}
    dir = mktempdir()
    ncells = 80
    data_file = joinpath(dir, "data.nc")
    NCDataset(data_file, "c", attrib = Dict{String, Any}("uuidOfHGrid" => "wl-1")) do ds
        defVar(ds, "time", collect(1:3), ("time",), attrib = Dict(
            "units" => "days since 2000-01-01 00:00:00"))
        defVar(ds, "temp", rand(ncells, 3), ("ncells", "time"), attrib = Dict(
            "units" => "K", "coordinates" => "clat clon"))
    end
    grid_file = joinpath(dir, "icon_grid_0001_R02B04_G.nc")
    NCDataset(grid_file, "c", attrib = Dict{String, Any}("uuidOfHGrid" => "wl-1")) do ds
        defVar(ds, "clon", rand(ncells) .* 6.0 .- 3.0, ("cell",), attrib = Dict(
            "standard_name" => "longitude", "units" => "radian"))
        defVar(ds, "clat", rand(ncells) .* 3.0 .- 1.5, ("cell",), attrib = Dict(
            "standard_name" => "latitude", "units" => "radian"))
    end
    data_file, grid_file
end

function exercise_grid_file!(args::Dict)::Nothing
    data_file, grid_file = create_workload_grid_pair()
    dataset = Data.CDFDataset([data_file], grid_file = grid_file)
    controller = Controller.ViewerController(
        dataset, headless = true, parsed_args = args, work_dir = pwd())
    state = ViewerREPL.REPLState(controller)
    ViewerREPL.evaluate_command(state, "v temp")
    ViewerREPL.evaluate_command(state, "p heatmap")
    foreach(wait, controller.fd.tasks[])
    GLMakie.closeall()
    close(dataset.ds)
    rm(dirname(data_file), recursive = true, force = true)
    nothing
end

function run_precompile_workload()::Nothing
    file = create_workload_file()
    with_logger(NullLogger()) do
        # Full headless pipeline, as the tests drive it
        args = ArgParse.parse_args([file], get_arg_parser())
        julia_main(parsed_args = args)

        # Interactive surface
        dataset = Data.CDFDataset([file])
        controller = Controller.ViewerController(
            dataset, headless = true, parsed_args = args, work_dir = pwd())
        state = ViewerREPL.REPLState(controller)
        exercise_repl_commands!(state)
        # Compile the line-editor setup (prompt, keymaps, history) without a TTY
        withenv("CDFVIEWER_HISTORY" => tempname()) do
            ViewerREPL.build_repl_interface(state)
        end
        GLMakie.closeall()
        close(dataset.ds)

        # External grid file support (merged-dataset code paths)
        exercise_grid_file!(args)
    end
    rm(file, force = true)
    nothing
end

@setup_workload begin
    @compile_workload begin
        try
            run_precompile_workload()
        catch e
            # Never fail precompilation (e.g. no GL context on CI machines);
            # the app still works, just without the cached native code.
            @warn "CDFViewer precompile workload failed" exception = (e, catch_backtrace())
        end
    end
end
