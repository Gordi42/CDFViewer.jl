module Data

using Dates
using Printf
using DataStructures
using NCDatasets
using NCDatasets.CommonDataModel: AbstractDataset
using ZarrDatasets: ZarrDataset
using GLMakie

import ..Constants
import ..GridFiles
import ..Interpolate
import ..RescaleUnits

# ============================================================
#  CDF Dataset
# ============================================================

struct CDFDataset
    ds::AbstractDataset
    dimensions::Vector{String}
    coordinates::Vector{String}
    variables::Vector{String}
    var_coords::OrderedDict{String, Vector{String}}
    paired_coords::Dict{String, Vector{String}}
    group_ids_of_var_dims::Dict{String, Vector{Int}}
    interp::Interpolate.Interpolator
    data_limits::Dict{String, Tuple{Float64, Float64}}
end

# ---------------------------------------------------
#  Opening (NetCDF files and zarr stores)
# ---------------------------------------------------

"""
    is_zarr_store(path) -> Bool

Whether `path` should be opened as a zarr store rather than a NetCDF file.
A path is treated as zarr when it ends in `.zarr`, or when it is a directory
(zarr stores are directories containing `.zgroup`/`.zmetadata`/`zarr.json`
metadata files; NetCDF files are never directories).
"""
function is_zarr_store(path::String)::Bool
    endswith(lowercase(rstrip(path, '/')), ".zarr") && return true
    # zarr stores are directories (containing .zgroup/.zmetadata/zarr.json
    # metadata files); NetCDF files never are.
    isdir(path)
end

"Open the given path(s) as a NetCDF dataset or a single zarr store."
function open_dataset(file_paths::Vector{String})::AbstractDataset
    for path in file_paths
        # Remote URLs are validated by the backends themselves
        occursin("://", path) && continue
        ispath(path) || error("File or directory not found: $path")
    end
    if any(is_zarr_store, file_paths)
        length(file_paths) > 1 && error(
            "Opening multiple paths is only supported for NetCDF files " *
            "(multi-file aggregation is NetCDF-only). " *
            "Please open a single zarr store instead.")
        store = file_paths[1]
        # A `zarr.json` at the store root marks zarr format v3, which the
        # Julia zarr stack (ZarrDatasets.jl on Zarr.jl 0.9) cannot read yet
        # — fail with a clear message instead of a cryptic backend error.
        isfile(joinpath(store, "zarr.json")) && error(
            "The store '$store' uses zarr format v3 (`zarr.json` metadata), " *
            "which is not yet supported by the Julia zarr stack " *
            "(ZarrDatasets.jl / Zarr.jl 0.9). " *
            "Please rewrite the store as zarr v2 to open it with CDFViewer.")
        return ZarrDataset(store, "r")
    end
    length(file_paths) == 1 && return NCDataset(file_paths[1], "r")
    NCDataset(file_paths, "r")
end

# ---------------------------------------------------
#  Constructors
# ---------------------------------------------------

function CDFDataset(
    file_paths::Vector{String};
    grid_file::String="",
    grid_search::Bool=true,
)::CDFDataset
    ds = open_dataset(file_paths)

    # Attach coordinates from an external grid file if needed
    ds = GridFiles.apply_grid(ds, file_paths; grid_file, grid_search)

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
        group_ids_of_var_dims, interp, Dict{String, Tuple{Float64, Float64}}()
    )
end

function get_var_coordinates(ds::AbstractDataset)::OrderedDict{String, Vector{String}}
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
                    # Only evict the auxiliary coordinate's *bare* index
                    # dimensions (those without a coordinate variable of
                    # their own, e.g. `ncells`). A dimension that is itself
                    # a coordinate variable — a dimension coordinate such as
                    # `time` — must survive: a 1-D auxiliary coordinate like
                    # an `iteration` counter along `time` supplements the
                    # dimension coordinate, it does not replace it.
                    removable = filter(d -> !haskey(ds, d), c_dims)
                    if isempty(removable)
                        # `c` shares its whole axis with existing dimension
                        # coordinate(s); keep those and leave `c` as a plain
                        # variable rather than adding a duplicate axis.
                        continue
                    end
                    v_coords = setdiff(v_coords, removable)
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
        ds::AbstractDataset,
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
    ds::AbstractDataset
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

function get_coord_order_priority(ds::AbstractDataset, coord::String)::Int
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

function sort_coordinates(ds::AbstractDataset, coords::Vector{String})::Vector{String}
    sort(coords, by = c -> get_coord_order_priority(ds, c))
end

# ---------------------------------------------------
#  Methods
# ---------------------------------------------------

function get_var_dims(dataset::CDFDataset, var::String)::Vector{String}
    return sort_coordinates(dataset.ds, dataset.var_coords[var])
end

function get_label(dataset::CDFDataset, var::String;
                   target_unit::Union{Nothing, String} = nothing)::String
    # some dimensions may not be stored as variables in the dataset
    var ∉ keys(dataset.ds) && return var
    # Get the attributes of the variable
    atts = dataset.ds[var].attrib
    # Get the long name and units
    label = haskey(atts, "long_name") ? atts["long_name"] : var
    unit = RescaleUnits.get_remapped_unit(dataset.ds, var)
    # An axis rendered in a converted display unit labels that unit instead
    if target_unit !== nothing
        native = RescaleUnits.get_unit(dataset.ds, var)
        if RescaleUnits.display_factor(native, target_unit) !== nothing
            unit = RescaleUnits.display_unit(target_unit).canonical
        end
    end
    if unit != ""
        label *= " [" * unit * "]"
    end
    return label
end

"Render a number with a runtime printf spec, falling back to \"%g\"."
function format_number(value::Number, numfmt::AbstractString)::String
    try
        return Printf.format(Printf.Format(String(numfmt)), value)
    catch
        return @sprintf("%g", value)
    end
end

"""
    get_dim_display_name(dataset, dim)

The human-readable name of `dim`: its `long_name` attribute when present,
otherwise the dimension name itself.
"""
function get_dim_display_name(dataset::CDFDataset, dim::String)::String
    dim ∉ keys(dataset.ds) && return dim
    atts = dataset.ds[dim].attrib
    haskey(atts, "long_name") ? String(atts["long_name"]) : dim
end

"The (remapped) unit of `dim`, or an empty string when it has none."
get_dim_unit(dataset::CDFDataset, dim::String)::String =
    dim ∉ keys(dataset.ds) ? "" : RescaleUnits.get_remapped_unit(dataset.ds, dim)

"""
    dim_unit_factor(dataset, dim, target_unit)

Multiplier taking native values of `dim` to values displayed in
`target_unit`, or nothing when no conversion applies (no target, unknown
dimension, or units from different families).
"""
function dim_unit_factor(
    dataset::CDFDataset, dim::String,
    target_unit::Union{Nothing, AbstractString},
)::Union{Float64, Nothing}
    target_unit === nothing && return nothing
    dim ∉ keys(dataset.ds) && return nothing
    RescaleUnits.display_factor(RescaleUnits.get_unit(dataset.ds, dim),
                                String(target_unit))
end

"The unit `dim` is displayed in: the converted unit when active, else native."
function get_dim_display_unit(
    dataset::CDFDataset, dim::String,
    target_unit::Union{Nothing, AbstractString},
)::String
    dim_unit_factor(dataset, dim, target_unit) === nothing &&
        return get_dim_unit(dataset, dim)
    RescaleUnits.display_unit(String(target_unit)).canonical
end

"""
    format_dim_value(dataset, dim, idx; numfmt, dateformat, target_unit)

The value of `dim` at index `idx`, formatted for display and *without* its
name or unit. Numbers use the printf spec `numfmt`, `DateTime` axes the
`Dates` format `dateformat`; anything unreadable falls back to the index.
A number is converted into `target_unit` when the dimension's native unit
allows it, and stays native otherwise.
"""
function format_dim_value(
    dataset::CDFDataset,
    dim::String,
    idx::Int;
    numfmt::AbstractString = Constants.NUMBER_FORMAT,
    dateformat::AbstractString = Constants.DATETIME_FORMAT,
    target_unit::Union{Nothing, AbstractString} = nothing,
)::String
    dim ∉ keys(dataset.ds) && return string(idx)
    value = Interpolate.get_coord_value(dataset.interp, dim, idx)
    isnothing(value) && return "Index $(idx) out of bounds"
    value isa Dates.DateTime && return Dates.format(value, dateformat)
    value isa AbstractString && return String(value)
    if value isa Number
        factor = dim_unit_factor(dataset, dim, target_unit)
        factor !== nothing && (value *= factor)
        return format_number(value, numfmt)
    end
    string(idx)
end

# ---------------------------------------------------
#  Compound durations
# ---------------------------------------------------

# component sizes in seconds, largest first
const DURATION_COMPONENTS = (
    (:d, 86400.0), (:h, 3600.0), (:m, 60.0), (:s, 1.0))

duration_component_index(c::Symbol)::Int =
    findfirst(p -> p[1] === c, DURATION_COMPONENTS)

"""
Shape of a compound-duration rendering ("12d 07:36"): the component the
label starts at, the one it stops at, and the decimals on a trailing
seconds component. Derived once per axis so every frame renders the same
shape and only the digits change.
"""
struct DurationSpec
    largest::Symbol    # :d, :h, :m or :s
    smallest::Symbol
    decimals::Int
end

# `r` counts of a component; integral up to formatting tolerance
near_multiple(r::Float64)::Bool = abs(r - round(r)) <= 1e-6 + abs(r) * 1e-12

"""
    derive_duration_spec(seconds)

The DurationSpec fitting an axis given its values in seconds: the leading
component covers the axis maximum, the trailing one is the largest
component every value is a whole number of (hourly data spanning years ->
"123d 07h"). Sub-second axes put their decimals on the seconds component.
"""
function derive_duration_spec(seconds)::DurationSpec
    vals = Float64[Float64(v) for v in seconds if v isa Number && isfinite(v)]
    isempty(vals) && return DurationSpec(:s, :s, 0)
    magnitude = maximum(abs, vals)
    steps = [abs(vals[i + 1] - vals[i]) for i in 1:(length(vals) - 1)]
    filter!(>(0.0), steps)
    step = isempty(steps) ? max(magnitude, 1.0) : minimum(steps)
    largest = :s
    for (c, f) in DURATION_COMPONENTS
        magnitude >= f && (largest = c; break)
    end
    smallest, decimals = :s, 0
    for (c, f) in DURATION_COMPONENTS
        f <= step * (1 + 1e-9) || continue     # must resolve the step
        if all(v -> near_multiple(v / f), vals)
            smallest = c
            break
        end
    end
    if smallest === :s && !all(v -> near_multiple(v), vals)
        for d in 1:9
            decimals = d
            all(v -> near_multiple(v * exp10(d)), vals) && break
        end
    end
    # the trailing component never precedes the leading one
    if duration_component_index(smallest) < duration_component_index(largest)
        smallest = largest
    end
    DurationSpec(largest, smallest, decimals)
end

"""
    format_duration(seconds, spec)

Render a length of time as a compound duration: days carry a "d" suffix,
the h/m/s chain is colon-joined and zero-padded ("12d 07:36:00"). A
chain of a single component keeps its unit letter ("12d 07h", "36m").
"""
function format_duration(seconds::Real, spec::DurationSpec)::String
    isfinite(seconds) || return string(seconds)
    li = duration_component_index(spec.largest)
    si = duration_component_index(spec.smallest)
    li = min(li, si)
    # decompose exactly, in integer counts of the finest resolution
    res = DURATION_COMPONENTS[si][2] *
        (spec.smallest === :s ? exp10(-spec.decimals) : 1.0)
    total = round(abs(Float64(seconds)) / res)
    total >= 9.2e18 && return format_number(seconds, "%g") * " s"
    n = Int64(total)
    texts = String[]
    for i in li:si
        per = round(Int64, DURATION_COMPONENTS[i][2] / res)
        q, n = divrem(n, per)
        c = DURATION_COMPONENTS[i][1]
        if c === :d
            push!(texts, "$(q)d")
        elseif c === :s && spec.decimals > 0
            push!(texts, @sprintf("%02d", q) * "." *
                         lpad(string(n), spec.decimals, '0'))
        else
            push!(texts, @sprintf("%02d", q))
        end
    end
    has_days = DURATION_COMPONENTS[li][1] === :d
    dstr = has_days ? texts[1] : ""
    chain = has_days ? texts[2:end] : texts
    body = if isempty(chain)
        dstr
    elseif length(chain) == 1
        letter = spec.smallest === :s && spec.decimals > 0 ? "s" :
            String(spec.smallest)
        (isempty(dstr) ? "" : dstr * " ") * chain[1] * letter
    else
        (isempty(dstr) ? "" : dstr * " ") * join(chain, ":")
    end
    (seconds < 0 && total > 0 ? "-" : "") * body
end

"""
    format_dim_label(dataset, dim, idx; fmt, numfmt, dateformat,
                     target_unit, durspec)

Render one axis' current value through the template `fmt`. Supported
placeholders are `{name}`, `{value}` (formatted value plus unit),
`{rawvalue}` (no unit), `{unit}`, `{index}` and `{duration}` (the value
as a compound time span, shaped by `durspec`). `DateTime` axes never take
a unit suffix. `target_unit` renders the value in a converted display
unit; `{duration}` falls back to the `{value}` rendering when `durspec`
is nothing or the axis is not a time span.
"""
function format_dim_label(
    dataset::CDFDataset,
    dim::String,
    idx::Int;
    fmt::AbstractString = Constants.ANIMLABEL_FORMAT,
    numfmt::AbstractString = Constants.NUMBER_FORMAT,
    dateformat::AbstractString = Constants.DATETIME_FORMAT,
    target_unit::Union{Nothing, AbstractString} = nothing,
    durspec::Union{Nothing, DurationSpec} = nothing,
)::String
    raw = format_dim_value(dataset, dim, idx; numfmt = numfmt,
                           dateformat = dateformat, target_unit = target_unit)
    value_obj = dim ∈ keys(dataset.ds) ?
        Interpolate.get_coord_value(dataset.interp, dim, idx) : nothing
    unit = value_obj isa Dates.DateTime ? "" :
        get_dim_display_unit(dataset, dim, target_unit)
    value_str = unit == "" ? raw : raw * " " * unit
    duration = value_str
    if durspec !== nothing && value_obj isa Number
        seconds_factor = dim_unit_factor(dataset, dim, "s")
        seconds_factor !== nothing &&
            (duration = format_duration(Float64(value_obj) * seconds_factor,
                                        durspec))
    end
    replace(String(fmt),
        "{name}" => get_dim_display_name(dataset, dim),
        "{value}" => value_str,
        "{rawvalue}" => raw,
        "{unit}" => unit,
        "{index}" => string(idx),
        "{duration}" => duration)
end

function get_dim_value_label(
    dataset::CDFDataset, dim::String, idx::Int;
    target_unit::Union{Nothing, AbstractString} = nothing,
)::String
    base = "  → "
    # Check if the dimension is selected
    dim === Constants.NOT_SELECTED_LABEL && return Constants.NO_DIM_SELECTED_LABEL
    # some dimensions may not be stored as variables in the dataset
    dim ∉ keys(dataset.ds) && return base * "$(dim): $(idx)"

    base = base * get_dim_display_name(dataset, dim) * ": "
    value = Interpolate.get_coord_value(dataset.interp, dim, idx)
    isnothing(value) && return base * "Index $(idx) out of bounds"
    # DateTimes carry their own formatting and take no unit suffix
    value isa Dates.DateTime &&
        return base * Dates.format(value, Constants.DATETIME_FORMAT)
    unit = get_dim_display_unit(dataset, dim, target_unit)
    unit = unit == "" ? "" : " " * unit
    value isa AbstractString && return base * value * unit
    if value isa Number
        factor = dim_unit_factor(dataset, dim, target_unit)
        factor !== nothing && (value *= factor)
        return base * format_number(value, Constants.NUMBER_FORMAT) * unit
    end
    return base * string(idx)
end

function get_dim_values(dataset::CDFDataset, dim::String)::Vector{Float64}
    dim === Constants.NOT_SELECTED_LABEL && return collect(Float64, 1:1)
    getproperty(dataset.interp.rc, Symbol(dim))
end

# ---------------------------------------------------
#  Dataset overview
# ---------------------------------------------------

_bold(s::AbstractString, color::Bool)::String =
    color ? Base.text_colors[:bold] * s * Base.text_colors[:normal] : String(s)

# Pad a string to a given display width (textwidth-aware, so "m/s²" and "…"
# line up correctly).
_pad(s::AbstractString, w::Int)::String = s * " "^max(0, w - textwidth(s))

function _dataset_name(dataset::CDFDataset)::String
    try
        p = NCDatasets.CommonDataModel.path(dataset.ds)
        p isa AbstractString && !isempty(p) && return basename(p)
    catch
    end
    # CommonDataModel.path is empty for zarr stores: use the store directory
    try
        ds = dataset.ds isa GridFiles.MergedDataset ? dataset.ds.ds : dataset.ds
        if ds isa ZarrDataset
            folder = ds.zgroup.storage.folder
            folder isa AbstractString && !isempty(folder) &&
                return basename(rstrip(folder, '/'))
        end
    catch
    end
    "dataset"
end

function _format_value(v)::String
    v isa Dates.DateTime && return Dates.format(v, Constants.DATETIME_FORMAT)
    v isa Number && return @sprintf("%g", v)
    v isa AbstractString && return String(v)
    string(v)
end

# (unit, range, length) description for a single coordinate.
function _coord_summary(dataset::CDFDataset, coord::String)::Tuple{String, String, Int}
    ds = dataset.ds
    unit = RescaleUnits.get_remapped_unit(ds, coord)
    if !haskey(ds, coord)
        # A bare dimension without a coordinate variable: size only.
        return unit, "", get(ds.dim, coord, 0)
    end
    len = length(ds[coord])
    range_str = ""
    try
        if eltype(ds[coord]) <: Dates.DateTime
            # Monotonic time axis: show the first and last stamp. The formatted
            # dates make the raw "<unit> since <date>" string redundant, so we
            # drop the unit to keep the column tight.
            lo = get_dim_value_endpoint(dataset, coord, 1)
            hi = get_dim_value_endpoint(dataset, coord, len)
            if lo isa Dates.DateTime || hi isa Dates.DateTime
                unit = ""
            end
            range_str = "$(_format_value(lo)) … $(_format_value(hi))"
        else
            vals = Interpolate.convert_to_float64(ds, coord)
            isempty(vals) ||
                (range_str = @sprintf("%g … %g", minimum(vals), maximum(vals)))
        end
    catch
    end
    unit, range_str, len
end

# Read a single coordinate value tolerantly (reuses the interpolator's
# broken-metadata fallbacks).
get_dim_value_endpoint(dataset::CDFDataset, coord::String, idx::Int) =
    Interpolate.get_coord_value(dataset.interp, coord, idx)

function _render_table(headers::Vector{String}, rows::Vector{Vector{String}},
        color::Bool)::String
    ncol = length(headers)
    widths = [maximum(vcat(textwidth(headers[c]),
                           [textwidth(r[c]) for r in rows]); init = 0)
              for c in 1:ncol]
    cell(s, w) = " " * _pad(s, w) * " "
    header = join([cell(headers[c], widths[c]) for c in 1:ncol], "│")
    sep = join(["─"^(widths[c] + 2) for c in 1:ncol], "┼")
    lines = [_bold(header, color), sep]
    for r in rows
        push!(lines, join([cell(r[c], widths[c]) for c in 1:ncol], "│"))
    end
    join(lines, "\n")
end

"""
    overview_string(dataset; color=true) -> String

A compact, human-readable summary of the dataset: file name and dimension
sizes, a coordinate block with units and value ranges, and a table of the data
variables with their dimensions, units and long names.
"""
function overview_string(dataset::CDFDataset; color::Bool = true)::String
    ds = dataset.ds
    io = IOBuffer()

    # Header line: file name + dimension sizes
    dims = sort_coordinates(ds, dataset.dimensions)
    dim_str = join(["$d:$(get(ds.dim, d, "?"))" for d in dims], "  ")
    println(io, _bold(_dataset_name(dataset), color), " — dims: ", dim_str)

    haskey(ds.attrib, "title") && println(io, "title: ", ds.attrib["title"])
    if dataset.ds isa GridFiles.MergedDataset
        println(io, "grid file: ", basename(dataset.ds.grid_path))
    end

    # Coordinate block: name  [unit]  lo … hi  (len)
    coords = sort_coordinates(ds, dataset.coordinates)
    if !isempty(coords)
        summaries = [(c, _coord_summary(dataset, c)) for c in coords]
        namew = maximum(textwidth.(coords))
        unitw = maximum([textwidth(isempty(u) ? "" : "[$u]")
                         for (_, (u, _, _)) in summaries]; init = 0)
        rangew = maximum([textwidth(r) for (_, (_, r, _)) in summaries]; init = 0)
        println(io, "\n", _bold("Coordinates:", color))
        for (c, (unit, range_str, len)) in summaries
            unit_str = isempty(unit) ? "" : "[$unit]"
            print(io, "  ", _pad(c, namew), "  ", _pad(unit_str, unitw))
            print(io, "  ", _pad(range_str, rangew))
            println(io, "  (", len, ")")
        end
    end

    # Data variable table
    headers = ["Variable", "Dimensions", "Units", "Long name"]
    rows = Vector{String}[]
    for var in dataset.variables
        var_dims = join(get_var_dims(dataset, var), ",")
        unit = RescaleUnits.get_remapped_unit(ds, var)
        atts = haskey(ds, var) ? ds[var].attrib : Dict{String, Any}()
        long_name = haskey(atts, "long_name") ? String(atts["long_name"]) : ""
        push!(rows, [var, var_dims, unit, long_name])
    end
    println(io, "")
    println(io, _render_table(headers, rows, color))

    String(take!(io))
end

function get_data_limits(dataset::CDFDataset, name::String)::Tuple{Float64, Float64}
    haskey(dataset.data_limits, name) && return dataset.data_limits[name]
    values = Interpolate.convert_to_float64(dataset.ds, name)
    dataset.data_limits[name] = (minimum(values), maximum(values))
    dataset.data_limits[name]
end

function get_dim_array(dataset::CDFDataset, dim::Observable{String}, update_switch::Observable{Bool})::Observable{Vector{Float64}}
    result = Observable(get_dim_values(dataset, dim[]))
    for trigger in (dim, update_switch)
        on(trigger) do _
            !(update_switch[]) && return
            result[] = get_dim_values(dataset, dim[])
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
