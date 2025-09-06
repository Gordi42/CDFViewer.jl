module Data

using Dates
using Printf
using NCDatasets
using GLMakie

import ..Constants

# ============================================================
#  CDF Dataset
# ============================================================

struct CDFDataset
    ds::NCDataset
    dimensions::Vector{String}
    variables::Vector{String}
end

# ---------------------------------------------------
#  Constructors
# ---------------------------------------------------

function CDFDataset(file_path::String)
    ds = NCDataset(file_path, "r")
    dimensions = collect(keys(ds.dim))
    variables = setdiff(collect(keys(ds)), dimensions)

    CDFDataset(ds, dimensions, variables)
end

# ---------------------------------------------------
#  Methods
# ---------------------------------------------------

function get_var_dims(dataset::CDFDataset, var::String)
    return collect(dimnames(dataset.ds[var]))
end

function get_label(dataset::CDFDataset, var::String)
    # some dimensions may not be stored as variables in the dataset
    var ∉ keys(dataset.ds) && return var
    # Get the attributes of the variable
    atts = dataset.ds[var].attrib
    # Get the long name and units
    label = haskey(atts, "long_name") ? atts["long_name"] : var
    if haskey(atts, "units")
        label *= " [" * atts["units"] * "]"
    end
    return label
end

function get_dim_value_label(dataset::CDFDataset, dim::String, idx::Int)
    base = "  → "
    # Check if the dimension is selected
    dim === Constants.NOT_SELECTED_LABEL && return Constants.NO_DIM_SELECTED_LABEL
    # some dimensions may not be stored as variables in the dataset
    dim ∉ keys(dataset.ds) && return base * "$(dim): $(idx)"
    # get name and unit attributes
    atts = dataset.ds[dim].attrib
    var_name = haskey(atts, "long_name") ? atts["long_name"] : dim
    unit = haskey(atts, "units") ? " " * atts["units"] : ""

    base = base * var_name * ": "
    idx > length(dataset.ds[dim]) && return base * "Index $(idx) out of bounds"
    value = dataset.ds[dim][idx]
    value isa Dates.DateTime && return base * Dates.format(value, Constants.DATETIME_FORMAT)
    value isa AbstractString && return base * value * unit
    value isa Number && return base * @sprintf("%g", value) * unit
    return base * string(idx)
end

function get_dim_values(dataset::CDFDataset, dim::String)
    dim === Constants.NOT_SELECTED_LABEL && return collect(Float64, 1:1)
    try
        return convert(Vector{Float64}, dataset.ds[dim][:])
    catch
        dim_len = dataset.ds.dim[dim]
        return Float64.(1:dim_len)
    end
end

function get_dim_array(dataset::CDFDataset, dim::Observable{String}, update_switch::Observable{Bool})
    result = Observable(Data.get_dim_values(dataset, dim[]))
    for trigger in (dim, update_switch)
        on(trigger) do _
            !(update_switch[]) && return
            result[] = Data.get_dim_values(dataset, dim[])
        end
    end
    result
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


end # module
