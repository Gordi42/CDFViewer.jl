module GridFiles

using TOML
using Downloads
using NCDatasets
const CDM = NCDatasets.CommonDataModel
const DiskArrays = CDM.DiskArrays
using .CDM: AbstractDataset, AbstractVariable

# ============================================================
#  Configuration
#
#  Read from ~/.config/cdfviewer/config.toml (override the location with
#  the CDFVIEWER_CONFIG environment variable):
#
#  [grid]
#  search = true                     # master switch for automatic search
#  search_dirs = ["~/grids"]         # searched in addition to the data dir
#  download = false                  # opt-in download of grid_file_uri
#  download_dir = "~/.cache/cdfviewer/grids"
# ============================================================

struct GridConfig
    search::Bool
    search_dirs::Vector{String}
    download::Bool
    download_dir::String
end

function default_config()::GridConfig
    GridConfig(true, String[], false, joinpath(homedir(), ".cache", "cdfviewer", "grids"))
end

function config_path()::String
    default_dir = get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config"))
    get(ENV, "CDFVIEWER_CONFIG", joinpath(default_dir, "cdfviewer", "config.toml"))
end

function load_config(path::String=config_path())::GridConfig
    d = default_config()
    isfile(path) || return d
    raw = try
        TOML.parsefile(path)
    catch e
        @warn "Could not parse config file '$path'" exception=e
        return d
    end
    grid = get(raw, "grid", Dict{String, Any}())
    GridConfig(
        get(grid, "search", d.search),
        [expanduser(String(p)) for p in get(grid, "search_dirs", String[])],
        get(grid, "download", d.download),
        expanduser(String(get(grid, "download_dir", d.download_dir))),
    )
end

# ============================================================
#  Missing coordinate detection
# ============================================================

"""
Coordinate names listed in some variable's `coordinates` attribute
that are not present in the dataset (grid stored in a separate file).
"""
function missing_coordinates(ds::AbstractDataset)::Vector{String}
    missing_coords = String[]
    for var in keys(ds)
        atts = ds[var].attrib
        haskey(atts, "coordinates") || continue
        for c in split(atts["coordinates"])
            (haskey(ds, c) || c in missing_coords) && continue
            push!(missing_coords, String(c))
        end
    end
    missing_coords
end

needs_grid_file(ds::AbstractDataset)::Bool = !isempty(missing_coordinates(ds))

# ============================================================
#  Grid file search
# ============================================================

function get_global_attrib(ds::AbstractDataset, name::String)::Union{String, Nothing}
    haskey(ds.attrib, name) || return nothing
    att = ds.attrib[name]
    att isa AbstractArray && (att = first(att))
    string(att)
end

function grid_number(ds::AbstractDataset)::Union{Int, Nothing}
    att = get_global_attrib(ds, "number_of_grid_used")
    att === nothing && return nothing
    tryparse(Int, att)
end

"Path relative to a pool root, e.g. \"mpim/0036/icon_grid_0036_R02B04_O.nc\"."
function pool_relative_path(uri::String)::Union{String, Nothing}
    m = match(r"grids/public/(.+)$", uri)
    m === nothing ? nothing : String(m.captures[1])
end

function readdir_safe(dir::String)::Vector{String}
    try
        readdir(dir)
    catch
        String[]
    end
end

"""
Light check whether a candidate file can serve as grid file for `data_ds`:
`uuidOfHGrid` must match when both files have one (always required with
`require_uuid`), and at least one missing coordinate must be present.
"""
function matches_grid(
    data_ds::AbstractDataset,
    candidate::String;
    require_uuid::Bool=false,
)::Bool
    data_uuid = get_global_attrib(data_ds, "uuidOfHGrid")
    try
        NCDataset(candidate, "r") do grid_ds
            grid_uuid = get_global_attrib(grid_ds, "uuidOfHGrid")
            if data_uuid !== nothing && grid_uuid !== nothing
                data_uuid == grid_uuid || return false
            elseif require_uuid
                return false
            end
            any(c -> haskey(grid_ds, c), missing_coordinates(data_ds))
        end
    catch e
        @warn "Could not open grid file candidate '$candidate'" exception=e
        false
    end
end

function download_grid_file(uri::String, config::GridConfig)::Union{String, Nothing}
    target = joinpath(config.download_dir, basename(uri))
    isfile(target) && return target
    @info "Downloading grid file from $uri to $(config.download_dir)"
    try
        mkpath(config.download_dir)
        Downloads.download(uri, target * ".part")
        mv(target * ".part", target)
        target
    catch e
        @warn "Grid file download failed" exception=e
        nothing
    end
end

"""
    find_grid_file(data_ds, data_dir, config) -> path or nothing

Resolution order (mirrors CDO): `grid_file_uri` basename in the search
directories (also relative to pool-style roots) → `icon_grid_<NNNN>_*.nc`
filename pattern → `uuidOfHGrid` scan over `icon_grid*.nc` files →
opt-in download of `grid_file_uri`.
"""
function find_grid_file(
    data_ds::AbstractDataset,
    data_dir::String,
    config::GridConfig,
)::Union{String, Nothing}
    dirs = String[data_dir]
    append!(dirs, config.search_dirs)
    config.download && push!(dirs, config.download_dir)
    dirs = unique(filter(isdir, dirs))

    uri = get_global_attrib(data_ds, "grid_file_uri")
    uuid = get_global_attrib(data_ds, "uuidOfHGrid")
    ngrid = grid_number(data_ds)

    # 1. by the URI's file name (and pool-style relative path)
    if uri !== nothing
        candidates = String[basename(uri)]
        rel = pool_relative_path(uri)
        rel === nothing || push!(candidates, rel)
        for dir in dirs, cand in candidates
            path = joinpath(dir, cand)
            isfile(path) && matches_grid(data_ds, path) && return path
        end
    end

    # 2. by the icon_grid_<NNNN>_*.nc naming convention
    if ngrid !== nothing
        prefix = "icon_grid_" * lpad(ngrid, 4, '0') * "_"
        for dir in dirs, f in readdir_safe(dir)
            (startswith(f, prefix) && endswith(f, ".nc")) || continue
            path = joinpath(dir, f)
            matches_grid(data_ds, path) && return path
        end
    end

    # 3. by uuidOfHGrid scan over icon_grid*.nc files
    if uuid !== nothing
        for dir in dirs, f in readdir_safe(dir)
            (startswith(f, "icon_grid") && endswith(f, ".nc")) || continue
            path = joinpath(dir, f)
            matches_grid(data_ds, path, require_uuid=true) && return path
        end
    end

    # 4. opt-in download
    if config.download && uri !== nothing
        return download_grid_file(uri, config)
    end

    nothing
end

# ============================================================
#  Merged dataset view
#
#  Presents the data file with the missing coordinate variables injected
#  from the grid file, exposed under the data file's dimension names
#  (grid files use `cell`/`vertex`/`edge`, data files use `ncells`, ...).
# ============================================================

struct MergedDataset <: AbstractDataset
    ds::AbstractDataset                # data file(s)
    grid_ds::AbstractDataset           # grid file
    grid_path::String
    # injected name => (name in grid file, dims renamed to data dims)
    grid_vars::Dict{String, Tuple{String, Vector{String}}}
end

struct MergedVariable{T, N} <: AbstractVariable{T, N}
    parent::MergedDataset
    var::AbstractVariable{T, N}        # variable in the grid file
    dims::NTuple{N, String}            # renamed to data-file dimensions
end

# --- AbstractVariable interface ---
CDM.name(v::MergedVariable) = CDM.name(v.var)
CDM.dimnames(v::MergedVariable) = v.dims
CDM.dataset(v::MergedVariable) = v.parent
CDM.attribnames(v::MergedVariable) = CDM.attribnames(v.var)
CDM.attrib(v::MergedVariable, name::CDM.SymbolOrString) = CDM.attrib(v.var, name)
Base.size(v::MergedVariable) = size(v.var)
Base.getindex(v::MergedVariable, indices...) = v.var[indices...]
function DiskArrays.readblock!(v::MergedVariable{T, N}, aout, indexes::Vararg{OrdinalRange, N}) where {T, N}
    DiskArrays.readblock!(v.var, aout, indexes...)
end
DiskArrays.eachchunk(v::MergedVariable) = DiskArrays.eachchunk(v.var)
DiskArrays.haschunks(v::MergedVariable) = DiskArrays.haschunks(v.var)

# --- AbstractDataset interface ---
function CDM.varnames(ds::MergedDataset)
    vcat(collect(String, keys(ds.ds)), collect(String, keys(ds.grid_vars)))
end

function CDM.variable(ds::MergedDataset, varname::CDM.SymbolOrString)
    name = String(varname)
    if haskey(ds.grid_vars, name)
        grid_name, dims = ds.grid_vars[name]
        var = CDM.variable(ds.grid_ds, grid_name)
        return MergedVariable(ds, var, Tuple(dims))
    end
    CDM.variable(ds.ds, varname)
end

CDM.dimnames(ds::MergedDataset) = CDM.dimnames(ds.ds)
CDM.dim(ds::MergedDataset, name::CDM.SymbolOrString) = CDM.dim(ds.ds, name)
CDM.attribnames(ds::MergedDataset) = CDM.attribnames(ds.ds)
CDM.attrib(ds::MergedDataset, name::CDM.SymbolOrString) = CDM.attrib(ds.ds, name)
CDM.path(ds::MergedDataset) = CDM.path(ds.ds)
CDM.maskingvalue(ds::MergedDataset) = CDM.maskingvalue(ds.ds)

function Base.close(ds::MergedDataset)
    close(ds.grid_ds)
    close(ds.ds)
end

# ============================================================
#  Verification and merging
# ============================================================

"Dimensions of all data variables that reference `coord` in their `coordinates` attribute."
function candidate_data_dims(data_ds::AbstractDataset, coord::String)::Vector{String}
    dims = String[]
    for var in keys(data_ds)
        atts = data_ds[var].attrib
        haskey(atts, "coordinates") || continue
        coord in split(atts["coordinates"]) || continue
        append!(dims, NCDatasets.dimnames(data_ds[var]))
    end
    unique(dims)
end

"""
Map every dimension of the grid variable to a data dimension of the same
size (among the dimensions of the variables referencing the coordinate).
Returns nothing if any dimension has no match or an ambiguous match.
"""
function map_grid_dims(
    data_ds::AbstractDataset,
    grid_ds::AbstractDataset,
    coord::String,
)::Union{Vector{String}, Nothing}
    candidates = candidate_data_dims(data_ds, coord)
    mapped = String[]
    for grid_dim in NCDatasets.dimnames(CDM.variable(grid_ds, coord))
        grid_len = grid_ds.dim[grid_dim]
        matches = [d for d in candidates if data_ds.dim[d] == grid_len]
        if length(matches) != 1
            reason = isempty(matches) ? "no data dimension with $grid_len entries" :
                "ambiguous data dimensions $(matches)"
            @warn "Cannot attach grid coordinate '$coord': $reason (grid dimension '$grid_dim')"
            return nothing
        end
        push!(mapped, matches[1])
    end
    mapped
end

function check_uuid(data_ds::AbstractDataset, grid_ds::AbstractDataset, explicit::Bool)::Bool
    data_uuid = get_global_attrib(data_ds, "uuidOfHGrid")
    grid_uuid = get_global_attrib(grid_ds, "uuidOfHGrid")
    (data_uuid === nothing || grid_uuid === nothing || data_uuid == grid_uuid) && return true
    msg = "uuidOfHGrid mismatch: data file has $data_uuid, grid file has $grid_uuid"
    # A user-supplied grid file may legitimately be a regenerated but
    # equivalent grid — warn instead of rejecting.
    explicit ? (@warn msg; true) : (@debug msg; false)
end

"""
    merge_grid_file(data_ds, grid_path; explicit) -> MergedDataset or nothing

Open `grid_path` and inject the coordinates that are missing from
`data_ds`. Every injected variable is verified by dimension size; the
grid uuid is verified when both files carry one.
"""
function merge_grid_file(
    data_ds::AbstractDataset,
    grid_path::String;
    explicit::Bool=false,
)::Union{MergedDataset, Nothing}
    grid_ds = NCDataset(grid_path, "r")
    if !check_uuid(data_ds, grid_ds, explicit)
        close(grid_ds)
        return nothing
    end

    grid_vars = Dict{String, Tuple{String, Vector{String}}}()
    for coord in missing_coordinates(data_ds)
        if !haskey(grid_ds, coord)
            explicit && @warn "Coordinate '$coord' not found in grid file '$grid_path'"
            continue
        end
        mapped = map_grid_dims(data_ds, grid_ds, coord)
        mapped === nothing && continue
        grid_vars[coord] = (coord, mapped)
    end

    if isempty(grid_vars)
        explicit && @warn "No usable coordinates found in grid file '$grid_path'"
        close(grid_ds)
        return nothing
    end

    MergedDataset(data_ds, grid_ds, grid_path, grid_vars)
end

# ============================================================
#  Entry point
# ============================================================

"""
    apply_grid(ds, file_paths; grid_file="", grid_search=true) -> dataset

Return `ds` with external grid coordinates attached when needed.
An explicitly given `grid_file` always wins; otherwise the configured
search directories are consulted for a matching grid file.
"""
function apply_grid(
    ds::AbstractDataset,
    file_paths::Vector{String};
    grid_file::String="",
    grid_search::Bool=true,
)
    explicit = !isempty(grid_file)

    if explicit
        isfile(grid_file) || error("Grid file not found: $grid_file")
        merged = merge_grid_file(ds, grid_file, explicit=true)
        merged === nothing && return ds
        @info "Attached grid file: $grid_file"
        return merged
    end

    needs_grid_file(ds) || return ds

    config = load_config()
    if !(grid_search && config.search)
        @info "Coordinates $(missing_coordinates(ds)) are not in the dataset " *
              "and grid file search is disabled. Pass --grid <file> to attach a grid file."
        return ds
    end

    data_dir = dirname(abspath(first(file_paths)))
    grid_path = find_grid_file(ds, data_dir, config)
    if grid_path === nothing
        @info "Coordinates $(missing_coordinates(ds)) are not in the dataset and " *
              "no matching grid file was found. Pass --grid <file> or add search " *
              "directories to $(config_path())."
        return ds
    end

    merged = merge_grid_file(ds, grid_path)
    merged === nothing && return ds
    @info "Attached grid file: $grid_path"
    merged
end

end # module
