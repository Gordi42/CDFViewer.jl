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
    coordinates::Vector{String}
    variables::Vector{String}
    var_coords::Dict{String, Vector{String}}
    paired_coords::Dict{String, Vector{String}}
end

# ---------------------------------------------------
#  Constructors
# ---------------------------------------------------

function CDFDataset(file_paths::Vector{String})::CDFDataset
    ds = if length(file_paths) == 1
        NCDataset(file_paths[1], "r")
    else
        NCDataset(file_paths, "r")
    end

    dimensions = collect(keys(ds.dim))
    var_coords = get_var_coordinates(ds)
    coordinates = unique(vcat(values(var_coords)...))
    variables = collect(keys(var_coords))
    paired_coords = Dict(coord => get_paired_coordinates(coord, var_coords, ds)
                         for coord in coordinates)

    CDFDataset(ds, dimensions, coordinates, variables, var_coords, paired_coords)
end

function get_var_coordinates(ds::NCDataset)::Dict{String, Vector{String}}
    dimensions = collect(keys(ds.dim))
    variables = setdiff(collect(keys(ds)), dimensions)
    possible_coords = union(dimensions, variables)

    var_coords = Dict{String, Vector{String}}()
    for var in variables
        # First get the dimensions of the variable (They are always coordinates)
        v_coords = collect(dimnames(ds[var]))

        # Then check the "coordinates" attribute (if it exists)
        atts = ds[var].attrib
        if haskey(atts, "coordinates")
            # Assume space-separated list of coordinates (e.g. "lat lon")
            att_coords = split(atts["coordinates"])
            for c in att_coords
                if c ∈ possible_coords
                    c_dims = collect(dimnames(ds[c]))
                    # remove the dependent dimensions of the coordinate variable
                    v_coords = setdiff(v_coords, c_dims)
                    push!(v_coords, c)
                else
                    @warn "Coordinate '$c' listed in 'coordinates' attribute of variable '$var' not found in dataset"
                end
            end
        end
        var_coords[var] = unique(v_coords)
    end

    # remove all variables that are itself coordinates of other variables
    coordinates = unique(vcat(values(var_coords)...))
    for coord in coordinates
        haskey(var_coords, coord) && delete!(var_coords, coord)
    end

    var_coords
end

function get_paired_coordinates(
        coord::String,
        var_coords::Dict{String, Vector{String}},
        ds::NCDataset,
        )::Vector{String}
    # If the coordinate is a dimension of the dataset, it has no paired coordinates
    coord ∈ keys(ds.dim) && return String[] 
    # Get the dimensions of the coordinate variable
    coord_dims = collect(dimnames(ds[coord]))
    # Check for "hidden" paired coordinates
    # Consider for example a variable with coords (time, lat, lon)
    # where both lat and lon share the same dimension (e.g. "ncells")
    # In this case, lat and lon are "hidden" paired coordinates
    paired_coords = String[]
    for v_coords in values(var_coords)
        coord ∉ v_coords && continue  # This variable does not depend on the coordinate
        for c in v_coords
            c ∈ keys(ds.dim) && continue  # Skip dimensions
            c == coord && continue  # Skip the original coordinate
            # Check if the variable shares any dimension with the coordinate
            c_dims = collect(dimnames(ds[c]))
            if !isempty(intersect(coord_dims, c_dims))
                push!(paired_coords, c)
            end
        end
    end
    # We remove duplicates and the original coordinate
    unique(setdiff(paired_coords, [coord]))
end

# ---------------------------------------------------
#  Methods
# ---------------------------------------------------

function get_var_dims(dataset::CDFDataset, var::String)::Vector{String}
    return collect(dimnames(dataset.ds[var]))
end

function get_label(dataset::CDFDataset, var::String)::String
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

function get_dim_value_label(dataset::CDFDataset, dim::String, idx::Int)::String
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

function get_dim_values(dataset::CDFDataset, dim::String)::Vector{Float64}
    dim === Constants.NOT_SELECTED_LABEL && return collect(Float64, 1:1)
    try
        return convert(Vector{Float64}, dataset.ds[dim][:])
    catch
        dim_len = dataset.ds.dim[dim]
        return Float64.(1:dim_len)
    end
end

function get_dim_array(dataset::CDFDataset, dim::Observable{String}, update_switch::Observable{Bool})::Observable{Vector{Float64}}
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
)::Vector{Union{Colon, Int}}
    [dim in plot_dimensions ? Colon() : dimension_selections[dim] for dim in var_dims]
end

function get_data(
    dataset::CDFDataset,
    variable::String,
    plot_dimensions::Vector{String},
    dimension_selections::Dict{String, Int},
)::Array
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

    # If there are missing values, convert to Float64 and replace missing with NaN
    if Missing <: eltype(data)
        data = replace(data, missing => NaN)
    end
    data
end


end # module
