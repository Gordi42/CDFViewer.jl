module Data

using NCDatasets
using GLMakie

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

function get_dim_values(dataset::CDFDataset, dim::String)
    dim === "Not Selected" && return Float64[]
    try
        return convert(Vector{Float64}, dataset.ds[dim][:])
    catch
        dim_len = dataset.ds.dim[dim]
        return Float64.(1:dim_len)
    end
end

function get_dim_array(dataset::CDFDataset, dim::Observable{String})
    @lift(get_dim_values(dataset, $dim))
end

function get_data_slice(
    var_dims::Vector{String},
    plot_dimensions::Vector{String},
    dimension_selections::Dict{String, Int},
)
    [dim in plot_dimensions ? Colon() : dimension_selections[dim] for dim in var_dims]
end

function get_data(
    dataset::CDFDataset,
    variable::String,
    plot_dimensions::Vector{String},
    dimension_selections::Dict{String, Int},
)
    # get the dimensions of the variable
    var_dims = collect(dimnames(dataset.ds[variable]))

    # get the slices
    slices = get_data_slice(var_dims, plot_dimensions, dimension_selections)
    data = dataset.ds[variable][slices...]

    # permute the data to match the order of plot_dimensions
    if length(plot_dimensions) > 1
        perm = sortperm([findfirst(==(dim), var_dims) for dim in plot_dimensions])
        data = permutedims(dataset.ds[variable][slices...], perm)
    end
    data
end

function get_label(dataset::CDFDataset, var::String)
    if !(var in keys(dataset.ds))
        # some dimensions may not be stored as variables in the dataset
        return var
    end
    atts = dataset.ds[var].attrib
    label = haskey(atts, "long_name") ? atts["long_name"] : var
    if haskey(atts, "units")
        label *= " [" * atts["units"] * "]"
    end
    return label
end

end # module
