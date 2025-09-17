module Data

using Dates
using Printf
using DataStructures
using NCDatasets
using GLMakie

import ..Constants
import ..Interpolate
import ..RescaleUnits

# ============================================================
#  CDF Dataset
# ============================================================

struct CDFDataset
    ds::NCDataset
    dimensions::Vector{String}
    coordinates::Vector{String}
    variables::Vector{String}
    var_coords::OrderedDict{String, Vector{String}}
    paired_coords::Dict{String, Vector{String}}
    group_ids_of_var_dims::Dict{String, Vector{Int}}
    interp::Interpolate.Interpolator
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
    # Sort the coordinates
    coordinates = sort_coordinates(ds, coordinates)
    variables = collect(keys(var_coords))
    paired_coords = Dict(coord => get_paired_coordinates(coord, var_coords, ds)
                         for coord in coordinates)
    interp = Interpolate.Interpolator(ds, paired_coords)
    group_ids_of_var_dims = get_group_ids_of_var_dims(interp, coordinates, var_coords)

    CDFDataset(
        ds, dimensions, coordinates, variables, var_coords, paired_coords,
        group_ids_of_var_dims, interp)
end

function get_var_coordinates(ds::NCDataset)::OrderedDict{String, Vector{String}}
    dimensions = collect(keys(ds.dim))
    variables = setdiff(collect(keys(ds)), dimensions)
    possible_coords = union(dimensions, variables)

    var_coords = OrderedDict{String, Vector{String}}()
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
        var_coords::OrderedDict{String, Vector{String}},
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

function get_coords_by_dim(
    coordinates::Vector{String},
    ds::NCDataset
)::Dict{String, Vector{String}}
    # coords by dimension is a mapping from each dimension to a list of coordinates
    # that depend on that dimension
    coords_by_dim = Dict(dim => String[] for dim in keys(ds.dim))
    for coord in coordinates
        if coord ∈ keys(ds.dim)
            push!(coords_by_dim[coord], coord)
            continue
        end
        coord_dims = collect(dimnames(ds[coord]))
        for dim in coord_dims
            push!(coords_by_dim[dim], coord)
        end
    end
    coords_by_dim
end

function get_group_ids_of_var_dims(
    interp::Interpolate.Interpolator,
    coordinates::Vector{String},
    var_coords::OrderedDict{String, Vector{String}}
)::Dict{String, Vector{Int}}

    coords_by_dim = get_coords_by_dim(coordinates, interp.ds)
    group_ids_of_var_dims = Dict{String, Vector{Int}}()

    # We loop over each variable and get the group ids of its dimensions
    for (var, coords) in var_coords
        # Start by setting the group ids to an empty array
        group_ids_if_this_var = Int[]
        # Get the dimension names of the variable
        var_dims = collect(dimnames(interp.ds[var]))
        # We now need to find the group id of each dimension
        for dim in var_dims
            # Find all coordinates that depend on this dimension
            coords_with_dim = coords_by_dim[dim]
            # Find the first coordinate that is also a coordinate of this variable
            for coord in coords_with_dim
                if coord ∈ coords
                    group_id = interp.group_map[coord]
                    # Add the group id to the list
                    push!(group_ids_if_this_var, group_id)
                    # We found a group id, so we can stop searching for this dimension
                    break
                end
            end
        end
        group_ids_of_var_dims[var] = group_ids_if_this_var
    end
    group_ids_of_var_dims
end

function get_coord_order_priority(ds::NCDataset, coord::String)::Int
    # if COORDINATE_ORDER_PRIORITY has an entry for the name, we return it
    haskey(Constants.COORDINATE_ORDER_PRIORITY, lowercase(coord)) && 
        return Constants.COORDINATE_ORDER_PRIORITY[lowercase(coord)]

    # otherwise we look if the coord has a standard_name attribute
    # and check if that is in the COORDINATE_ORDER_PRIORITY
    if haskey(ds, coord)
        atts = ds[coord].attrib
        if haskey(atts, "standard_name")
            std_name = atts["standard_name"]
            haskey(Constants.COORDINATE_ORDER_PRIORITY, lowercase(std_name)) && 
                return Constants.COORDINATE_ORDER_PRIORITY[lowercase(std_name)]
        end
    end

    # If we still didn't find anything, we return a high number
    return 99
end

function sort_coordinates(ds::NCDataset, coords::Vector{String})::Vector{String}
    sort(coords, by = c -> get_coord_order_priority(ds, c))
end

# ---------------------------------------------------
#  Methods
# ---------------------------------------------------

function get_var_dims(dataset::CDFDataset, var::String)::Vector{String}
    return sort_coordinates(dataset.ds, dataset.var_coords[var])
end

function get_label(dataset::CDFDataset, var::String)::String
    # some dimensions may not be stored as variables in the dataset
    var ∉ keys(dataset.ds) && return var
    # Get the attributes of the variable
    atts = dataset.ds[var].attrib
    # Get the long name and units
    label = haskey(atts, "long_name") ? atts["long_name"] : var
    unit = RescaleUnits.get_remapped_unit(dataset.ds, var)
    if unit != ""
        label *= " [" * unit * "]"
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
    unit = RescaleUnits.get_remapped_unit(dataset.ds, dim)
    unit = unit == "" ? "" : " " * unit

    base = base * var_name * ": "
    value = Interpolate.get_coord_value(dataset.interp, dim, idx)
    isnothing(value) && return base * "Index $(idx) out of bounds"
    value isa Dates.DateTime && return base * Dates.format(value, Constants.DATETIME_FORMAT)
    value isa AbstractString && return base * value * unit
    value isa Number && return base * @sprintf("%g", value) * unit
    return base * string(idx)
end

function get_dim_values(dataset::CDFDataset, dim::String)::Vector{Float64}
    dim === Constants.NOT_SELECTED_LABEL && return collect(Float64, 1:1)
    getproperty(dataset.interp.rc, Symbol(dim))
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

function get_indexing(
    group_ids::Vector{Int},
    plot_dimensions::Vector{String},
    dim_selection::Dict{String, Int},
    interp::Interpolate.Interpolator,
)
    # Create a list of indexing instructions indicating which dimensions need to be 
    # kept with Colon() and which need to be replaced by an index
    indexing = Vector{Union{Colon, Int}}()

    for gid in group_ids
        # If the group has more than one coordinate, we need to keep it as Colon()
        # In order to do the interpolation correctly
        if length(interp.groups[gid]) > 1
            push!(indexing, Colon())
            continue
        end
        coord = interp.groups[gid][1]
        # If the coordinate is one of the plot dimensions, we need to keep it as Colon()
        if coord in plot_dimensions
            push!(indexing, Colon())
            continue
        end
        # If the coordinate has a range set, we need to keep it as Colon()
        # In order to do the interpolation correctly
        if !isnothing(interp.ranges[coord])
            push!(indexing, Colon())
            continue
        end
        # Otherwise, we can replace it by an index
        push!(indexing, dim_selection[coord])
    end
    indexing
end

function get_data_group_ids(
    group_ids::Vector{Int},
    indexing::Vector{Union{Colon, Int}},
)::Vector{Int}
    [gid for (gid, idx) in zip(group_ids, indexing) if idx === Colon()]
end

function compute_new_shape(
    current_shape::Tuple{Vararg{Int}},
    group_ids::Vector{Int},
)::Tuple{Vararg{Int}}
    Tuple(prod(current_shape[findall(==(gid), group_ids)]) for gid in unique(group_ids))
end

function get_permutation_to_group_dims(
    group_ids::Vector{Int},
)::Vector{Int}
    vcat([findall(==(gid), group_ids) for gid in unique(group_ids)]...)
end

function reshape_data_to_groups(data::Array, new_group_ids::Vector{Int})::Array
    # Let's assume we have an array with size (a, b, c, d, e, f)
    # and with group ids [1, 2, 1, 3, 3, 2]
    # We first permute the dimensions so that group ids are next to each other
    # In this case, we would get the size (a, c, b, f, d, e), group ids [1, 1, 2, 2, 3, 3]
    # and permutation [1, 3, 2, 6, 4, 5]
    # We then reshape the array to (a*c, b*f, d*e), group ids [1, 2, 3]
    ndims(data) == 0 && return data  # Handle scalar case
    length(new_group_ids) == 0 && return data  # Handle empty group case

    new_shape = compute_new_shape(size(data), new_group_ids)
    perm = get_permutation_to_group_dims(new_group_ids)
    reshape(permutedims(data, perm), new_shape)
end

function filter_dim_selection(
    dim_selection::Dict{String, Int},
    dims::Vector{String},  # dimensions to exclude
)::Dict{String, Int}
    Dict(k => v for (k, v) in dim_selection if k ∉ dims)
end

function get_data(
    dataset::CDFDataset,
    variable::String,
    plot_dimensions::Vector{String},
    dimension_selections::Dict{String, Int},
)::Array
    interp = dataset.interp
    # Get the group ids of each dimension
    # For example, a variable may have dimensions (d1, d2, d3, d4)
    # where (d2 and d4) share the same group
    # Then the group ids would be [1, 2, 3, 2]  # or different numbers
    group_ids = dataset.group_ids_of_var_dims[variable]
    # Get the indexing instructions
    indexing = get_indexing(group_ids, plot_dimensions, dimension_selections, interp)
    # Read the raw data
    data = dataset.ds[variable][indexing...]
    # If there are missing values, convert to Float64 and replace missing with NaN
    if Missing <: eltype(data)
        data = replace(data, missing => NaN)
    end
    # Get the new group ids after indexing
    new_group_ids = get_data_group_ids(group_ids, indexing)
    # Reshape the data to group dimensions with the same group id into one dimension
    data = reshape_data_to_groups(data, new_group_ids)
    # Get the group ids after reshaping
    new_group_ids = unique(new_group_ids)
    # Get the groups of each ids
    data_dimensions = [interp.groups[gid] for gid in new_group_ids]
    # filter the dimension selection to not include the plot dimensions
    filtered_selection = filter_dim_selection(dimension_selections, plot_dimensions)
    # Now we perform the interpolation
    Interpolate.interpolate(
        interp,
        data,
        data_dimensions,
        plot_dimensions,
        filtered_selection,
    )
end


end # module
