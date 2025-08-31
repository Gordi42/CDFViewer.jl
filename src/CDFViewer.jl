module CDFViewer

using NCDatasets

include("Data.jl")
include("Plotting.jl")
include("UI.jl")

export open_viewer

"""
    open_viewer(file_path::String) -> Figure

Open an interactive NetCDF viewer for the given file.
"""
function open_viewer(file_path::String)
    ds = NCDataset(file_path, "r")
end

greet() = print("Hello World!")

end # module CDFViewer
