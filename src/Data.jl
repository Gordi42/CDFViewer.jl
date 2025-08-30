module Data

using NCDatasets

struct CDFDataset
    ds::NCDataset
    dimensions::Vector{String}
    variables::Vector{String}
end

function open_dataset(file_path::String)
    ds = NCDataset(file_path, "r")
    dimensions = collect(keys(ds.dim))
    variables = setdiff(collect(keys(ds)), dimensions)
    return CDFDataset(ds, dimensions, variables)
end

"Get dimension values as Float64 vector."
function get_dim_values(dataset::CDFDataset, dim::String)
    try
        return convert(Vector{Float64}, dataset.ds[dim][:])
    catch
        return Float64.(1:length(dataset.ds[dim]))
    end
end

"Get a human-readable label with long_name and units."
function get_label(dataset::CDFDataset, var::String)
    atts = dataset.ds[var].attrib
    label = haskey(atts, "long_name") ? atts["long_name"] : var
    if haskey(atts, "units")
        label *= " [" * atts["units"] * "]"
    end
    return label
end

end # module
