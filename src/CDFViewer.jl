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
    file_path = ARGS[1]

    println("Loading dataset from file: $file_path")

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
