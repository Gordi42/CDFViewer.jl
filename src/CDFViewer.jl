module CDFViewer

using NCDatasets

include("Constants.jl")
include("Parsing.jl")
include("Data.jl")
include("UI.jl")
include("Plotting.jl")
include("Controller.jl")

export julia_main

function julia_main()::Cint
    println("Running CDFViewer: $(Constants.APP_VERSION)")

    if length(ARGS) < 1
        println("Error: No NetCDF file path provided.")
        println("Usage: cdfviewer <path_to_netcdf_file> [additional arguments...]")
        return 1
    end

    file_path = ARGS[1]
    println("Loading dataset from file: $file_path")

    dataset = try
        Data.CDFDataset(file_path)
    catch e
        println("Error: Failed to open NetCDF file. Details: $e")
        return 1
    end

    println("Open Figure window...")
    controller = Controller.ViewerController(dataset)
    gl_screen = display(controller.fd.fig)
    println("Setup UI...")
    Controller.setup!(controller)
    println("Ready.")

    wait(gl_screen)

    return 0
end

function open_test()::Nothing
    include(joinpath(@__DIR__, "..", "test", "test_setup.jl"))
    
    controller = Controller.ViewerController(make_temp_dataset())
    display(controller.fd.fig)
    Controller.setup!(controller)
    nothing
end

export open_test

end # module CDFViewer
