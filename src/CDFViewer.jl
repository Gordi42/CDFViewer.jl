module CDFViewer

using GLMakie

include("Constants.jl")
include("Parsing.jl")
include("Data.jl")
include("UI.jl")
include("Plotting.jl")
include("Controller.jl")

export julia_main

function julia_main(args::Vector{String} = ARGS;
    wait_for_ui::Bool = true,
    visible::Bool = true,
)::Cint
    println("Running CDFViewer: $(Constants.APP_VERSION)")

    if length(args) < 1
        println("Error: No NetCDF file path provided.")
        println("Usage: cdfviewer <path_to_netcdf_file> [additional arguments...]")
        return 1
    end

    file_path = args[1]
    println("Loading dataset from file: $file_path")

    dataset = try
        Data.CDFDataset(file_path)
    catch e
        println("Error: Failed to open NetCDF file. Details: $e")
        return 1
    end

    println("Open Figure window...")
    controller = Controller.ViewerController(dataset)
    screen = GLMakie.Screen(visible=visible)
    display(screen, controller.fd.fig)
    println("Setup UI...")
    Controller.setup!(controller)
    println("Ready.")

    if wait_for_ui
        wait(screen)
    end

    return 0
end

end # module CDFViewer
