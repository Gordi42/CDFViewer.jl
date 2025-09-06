module CDFViewer

using NCDatasets

include("Constants.jl")
include("Parsing.jl")
include("Data.jl")
include("UI.jl")
include("Plotting.jl")
include("Controller.jl")

export open_viewer

"""
    open_viewer(file_path::String) -> Figure

Open an interactive NetCDF viewer for the given file.
"""
function open_viewer(file_path::String)
    ds = NCDataset(file_path, "r")
end

end # module CDFViewer
