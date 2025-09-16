module Interpolate

using NearestNeighbors
using NCDatasets

using ..Constants


struct LazyTree
    compute_func::Function
    _cache::Ref{Union{Nothing, KDTree}}
    
    LazyTree(f::Function) = new(f, Ref{Union{Nothing, KDTree}}(nothing))
end

function Base.getindex(lt::LazyTree)
    if isnothing(lt._cache[])
        lt._cache[] = lt.compute_func()
    end
    lt._cache[]
end

struct Interpolator
    ranges::Dict{String, Union{AbstractArray, Nothing}}
    group_map::Dict{String, Int}  # Map from coordinate to group index
    groups::Dict{Int, Vector{String}}
    index_cache::Dict{Int, Any}
    trees::Dict{Int, LazyTree}  # Map from group index to KDTree (lazily computed)
    ds::NCDataset  # Store the dataset for range computations
end

# ====================================================
#  Construction
# ====================================================

function Interpolator(
    ds::NCDataset,
    paired_coords::Dict{String, Vector{String}}
)::Interpolator
    ranges = Dict{String, Union{AbstractArray, Nothing}}()
    group_map = Dict{String, Int}()
    groups = Dict{Int, Vector{String}}()
    index_cache = Dict{Int, Array{Int}}()
    trees = Dict{Int, LazyTree}()
    i = 1
    for coord in keys(paired_coords)
        # Compute the range for this coordinate
        ranges[coord] = length(paired_coords[coord]) == 0 ? nothing : compute_range(ds, coord)
        # Skip if the tree is already computed
        coord ∈ keys(group_map) && continue
        # Add a lazy tree computation
        trees[i] = LazyTree( () -> compute_tree(ds, coord, paired_coords) )
        # Store the tree and the ordered paired coordinates
        groups[i] = [coord; paired_coords[coord]]
        for c in [coord; paired_coords[coord]]
            group_map[c] = i
        end
        i += 1
    end

    return Interpolator(ranges, group_map, groups, index_cache, trees, ds)
end

function compute_tree(
    ds::NCDataset,
    coord::String,
    paired_coords::Dict{String, Vector{String}},
    )::KDTree
    relevant_coords = [coord; paired_coords[coord]]
    coord_values = [convert_to_float64(ds, c) for c in relevant_coords]

    # Create the points matrix for the KDTree
    points = hcat(coord_values...)'  # Each row is a coordinate
    

    # For big datasets (>500 000 points), we print an info message
    if size(points, 2) > 500_000
        @info """
The unstructured coordinates: $(relevant_coords) have $(size(points, 2)) points. 
This may take a while to compute the KDTree (required for interpolation)."""
    end

    # Create and return the KDTree
    KDTree(points)
end

function compute_range(
    ds::NCDataset,
    coord::String,
    )::AbstractRange

    values = convert_to_float64(ds, coord)

    LinRange(minimum(values), maximum(values), Constants.N_INTERPOLATION_POINTS)
end

# ====================================================
#  Control Properties
# ====================================================

function set_range!(
    interp::Interpolator,
    coord::String,
    new_range::Union{AbstractArray, Nothing}
)::Nothing
    # check whether the coord is paired with other coordinates
    # if so, we cannot set the range to nothing
    if isnothing(new_range) && length(interp.groups[interp.group_map[coord]]) > 1
        new_range = compute_range(interp.ds, coord)
    end
    # if the new range is the same as the old, we don't need to do anything
    new_range === interp.ranges[coord] && return nothing
    # set the new range
    interp.ranges[coord] = new_range
    # remove the index cache of the group containing this coordinate
    # since the nearest neighbor indices must be recomputed
    group_id = interp.group_map[coord]
    delete!(interp.index_cache, group_id)
    nothing
end

# ====================================================
#  Interpolation
# ====================================================

function interpolate(
    interp::Interpolator,
    data::Array,
    data_dimensions::Vector{Vector{String}},
    output_dimensions::Vector{String},
    dim_selection::Dict{String, Int},
)::Array
    # Here is a sketch of what the function should do:
    # Let data be an array of size (nx, ny, nz)
    # data_dimensions tells what coordinates are associated to each dimension (can be multiple)
    # for example: data_dimensions = Dict(1 => ["time"], 2 => ["lat", "lon"], 3 => ["depth"])
    # output_dimensions tells the desired output dimensions, for example: ["time", "lat", "depth"]
    # dim_selection tells the selected index for each dimension that is not in output_dimensions.
    # for example: dim_selection = Dict("lon" => 10)
    # The output array will have size (nt, nlat, ndepth)
    # where nt is the size of the time dimension, nlat is the size of the lat dimension, and ndepth is the size of the depth dimension.

    # The algorithm works as follows:
    # Identify dimensions to interpolate (These are not only the dimensions that 
    # are associated with multiple coordinates, but also those that have a range in interp.ranges)
    # Then we interpolate one dimension at a time.

    # Interpolate each dimension
    axis_offset = 0
    new_data_dimensions = String[]
    for axis in 1:length(data_dimensions)
        dims = data_dimensions[axis]
        # Skip single dimensions with no range
        if length(dims) == 1 && isnothing(interp.ranges[dims[1]])
            push!(new_data_dimensions, dims...)
            continue  # No interpolation needed
        end

        # Interpolate this dimension
        group = interp.groups[interp.group_map[dims[1]]]
        this_dim_selection = get_this_dim_selection(dim_selection, group)
        data, pushed_dims = interpolate_dimension(
            interp,
            data,
            axis + axis_offset,
            dims,
            this_dim_selection,
        )

        # Compute a possible axis offset (if a dimension has been added)
        axis_offset += (length(pushed_dims) - 1)
        append!(new_data_dimensions, pushed_dims)
    end

    # Reorder the dimensions to match output_dimensions
    reorder_dimensions(data, new_data_dimensions, output_dimensions)
end

function interpolate_dimension(
    interp::Interpolator,
    data::Array,
    axis::Int,
    data_dimensions::Vector{String},
    dim_selection::Dict{String, Int},
)
    # Get the group for these data_dimensions
    group_id = interp.group_map[data_dimensions[1]]
    group = interp.groups[group_id]

    # Get the nearest neighbor indices for this group
    nn_indices = get_nn_indices(interp, group_id)
    # Filter with the dim_selection
    nn_indices = filter_nn_selection(nn_indices, dim_selection, group)

    # Compute the new shape of the data after interpolation
    new_coords = compute_filtered_group_coords(group, dim_selection)
    new_shape = compute_new_shape(size(data), size(nn_indices), axis)

    # Prepare the output array
    new_data = similar(data, Tuple(new_shape))

    # Get the interpolation axes of the output array
    int_axes = collect(axis:axis+length(new_coords)-1)

    # Interpolate each slice along the axis
    apply_on_axis!(data, new_data, axis, int_axes, s -> s[nn_indices])
    new_data, new_coords
end

function reorder_dimensions(
    data::Array,
    current_dimensions::Vector{String},
    output_dimensions::Vector{String},
)::Array
    # Create a mapping from dimension name to its current index
    dim_to_index = Dict(dim => idx for (idx, dim) in enumerate(current_dimensions))

    # Create the permutation order based on output_dimensions
    perm_order = [dim_to_index[dim] for dim in output_dimensions]

    # Permute the data array to match the desired order
    permutedims(data, perm_order)
end

# ====================================================
#  Interpolation helpers
# ====================================================
function apply_on_axis!(
    input_data::Array,
    output_data::Array,
    in_axis::Int,
    out_axes::Vector{Int},
    func::Function,
)::Nothing
    input_slices = eachslice(input_data, dims=Tuple(ax for ax in 1:ndims(input_data) if ax != in_axis))
    output_slices = eachslice(output_data, dims=Tuple(ax for ax in 1:ndims(output_data) if ax ∉ out_axes))
    for (in_s, out_s) in zip(input_slices, output_slices)
        out_s .= func(in_s)
    end
    return nothing
end

function compute_new_shape(
    old_shape::Tuple,
    index_shape::Tuple,
    axis::Int,
)::Tuple
    new_shape = collect(old_shape)[1:axis-1]
    append!(new_shape, index_shape)
    append!(new_shape, collect(old_shape)[axis+1:end])
    Tuple(new_shape)
end

function compute_filtered_group_coords(
    group::Vector{String},
    dim_selection::Dict{String, Int},
)::Vector{String}
    filter(c -> !(c in keys(dim_selection)), group)
end

function get_this_dim_selection(
    dim_selection::Dict{String, Int},
    group::Vector{String},
)::Dict{String, Int}
    # only take the (key, values) in dim_selection where the key is in group
    relevant_keys = intersect(keys(dim_selection), group)
    Dict(k => dim_selection[k] for k in relevant_keys)
end

# ====================================================
#  Nearest neighbor indexing helpers
# ====================================================

function get_indexing_tuple(
    group::Vector{String},
    dim_selection::Dict{String, Int},
)::Tuple{Vararg{Union{Colon, Int}}}
    # Create an indexing tuple for the group based on dim_selection
    Tuple( (dim in keys(dim_selection) ? dim_selection[dim] : Colon() for dim in group) )
end

function filter_nn_selection(
    nn_indices::Array{Int},
    dim_selection::Dict{String, Int},
    group::Vector{String},
)::SubArray{Int}
    indices = get_indexing_tuple(group, dim_selection)
    view(nn_indices, indices...)
end

function get_nn_indices(
    interp::Interpolator,
    group_id::Int,
)::Array{Int}
    # Find the group that contains these data_dimensions
    index_cache = interp.index_cache
    haskey(index_cache, group_id) && return index_cache[group_id]
    group = interp.groups[group_id]
    tree = interp.trees[group_id][]
    coords = [interp.ranges[c] for c in group]
    println("Computing nearest neighbor indices for group: ", group)
    println("Using ranges: ", coords)

    nn_indices = compute_nn_indices(tree, coords)
    index_cache[group_id] = nn_indices
    nn_indices
end

function compute_nn_indices(
    tree::KDTree,
    coords::Vector{<:AbstractVector{<:Real}},
)::Array{Int}
    new_shape = [length(c) for c in coords]
    # Create output array
    nn_indices = Array{Int}(undef, Tuple(new_shape))
    
    # Use CartesianIndices to ensure correct ordering
    cart_indices = CartesianIndices(Tuple(length.(coords)))
    
    # Collect query points in the same order as CartesianIndices
    query_points = Matrix{Float64}(undef, length(coords), length(cart_indices))
    
    for (linear_idx, cart_idx) in enumerate(cart_indices)
        for (coord_idx, coord_array) in enumerate(coords)
            query_points[coord_idx, linear_idx] = coord_array[cart_idx[coord_idx]]
        end
    end
    
    # Perform nearest neighbor search
    knn_indices, _ = nn(tree, query_points)
    indices = [idx[1] for idx in knn_indices]
    
    # Assign results using CartesianIndices (guaranteed correct mapping)
    for (linear_idx, cart_idx) in enumerate(cart_indices)
        nn_indices[cart_idx] = indices[linear_idx]
    end
    nn_indices
end

# ====================================================
#  Data collection helpers
# ====================================================

function convert_to_float64(ds::NCDataset, coord::String)::Vector{Float64}
    try
        convert(Vector{Float64}, ds[coord][:])
    catch
        dim_len = ds.dim[coord]
        Float64.(1:dim_len)
    end
end

function get_coord_value(
    interp::Interpolator,
    coord::String,
    index::Int,
)
    arr = isnothing(interp.ranges[coord]) ? interp.ds[coord] : interp.ranges[coord]
    index > length(arr) && return nothing
    arr[index]
end





# ====================================================
#  Property overloading for easier access
# ====================================================

struct RangeControl
    interp::Interpolator
end

function Base.propertynames(rc::RangeControl)
    coords = collect(keys(rc.interp.group_map))
    # return the coords as symbols
    Tuple(Symbol.(coords))
end

function Base.setproperty!(rc::RangeControl, coord::Symbol, new_range::Union{AbstractArray, Nothing})::RangeControl
    coord_str = String(coord)
    set_range!(rc.interp, coord_str, new_range)
    return rc
end

function Base.getproperty(rc::RangeControl, name::Symbol)::Union{AbstractArray, Nothing, Interpolator}
    if name === :interp
        return getfield(rc, :interp)
    end
    coord_str = String(name)
    range = rc.interp.ranges[coord_str]
    !isnothing(range) && return range
    convert_to_float64(rc.interp.ds, coord_str)
end

function Base.getproperty(interp::Interpolator, name::Symbol)
    if name === :rc
        return RangeControl(interp)
    end
    getfield(interp, name)
end

end
