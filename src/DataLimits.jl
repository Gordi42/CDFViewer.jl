module DataLimits

# Extrema of native hyperslabs.
#
# Powers the pinned color range: the extrema of everything an animation
# can show are the extrema of the variable's native hyperslab with the
# playback dimension left whole -- resampling (nearest-neighbor or
# linear) never leaves the range of the values it draws from, so bounds
# computed on the raw storage hold for every rendered frame. Reads are
# chunked so large variables never materialize at once, and a scan can
# be aborted between chunks once its result is no longer wanted.

import ..Data

# Elements per chunked read (~8 MB of Float64). Scans share the UI
# thread and each read blocks it, so chunks must stay small enough that
# the pauses between yields are imperceptible.
const CHUNK_ELEMENTS = 1_000_000

# The default (unrequested) pin only scans hyperslabs up to this many
# values (~128 MB of Float64); larger views keep per-frame scaling until
# the user explicitly asks. A Ref so tests can lower it.
const AUTO_SCAN_ELEMENTS = Ref(16_000_000)

"""
    scan_indexing(dataset, variable, keep, selection)

The hyperslab of `variable` covering every value the current view can
reach: the dimensions named in `keep` (plot axes, the playback
dimension) stay whole, the rest are fixed at their `selection` index.
Doubles as the cache key of a scan -- two views mapping to the same
hyperslab share a result.
"""
function scan_indexing(
    dataset::Data.CDFDataset,
    variable::String,
    keep::Vector{String},
    selection::Dict{String, Int},
)::Vector{Union{Colon, Int}}
    group_ids = dataset.group_ids_of_var_dims[variable]
    Data.get_indexing(group_ids, keep, selection, dataset.interp)
end

"""
    hyperslab_elements(dataset, variables, indexing)

Number of values the scan reads -- known before reading a single byte, so
callers can decide whether a scan is affordable. Every variable
contributes one hyperslab, so a two-component vector plot reads twice as
much as a scalar one.
"""
function hyperslab_elements(
    dataset::Data.CDFDataset,
    variables::Vector{String},
    indexing::Vector{Union{Colon, Int}},
)::Int
    isempty(variables) && return 0
    sz = size(dataset.ds[variables[1]])
    length(sz) == length(indexing) || return 0
    n = 1
    for i in eachindex(indexing)
        indexing[i] isa Colon && (n *= sz[i])
    end
    n * length(variables)
end

hyperslab_elements(dataset::Data.CDFDataset, variable::String,
                   indexing::Vector{Union{Colon, Int}})::Int =
    hyperslab_elements(dataset, [variable], indexing)

"""
    scan_value(components...)

Reduce one element's components to the scalar the scan tracks: a lone
value counts as itself, several count as their Euclidean magnitude --
what a vector plot colors its arrows by.
"""
scan_value(value::Float64)::Float64 = value
scan_value(u::Float64, v::Float64)::Float64 = hypot(u, v)
scan_value(values::Float64...)::Float64 = sqrt(sum(abs2, values))

"Apply the combiner without splatting a runtime-length vector."
function apply_combine(combine::Function, buffer::Vector{Float64})::Float64
    length(buffer) == 1 && return combine(buffer[1])
    length(buffer) == 2 && return combine(buffer[1], buffer[2])
    combine(buffer...)
end

"""
    hyperslab_extrema(dataset, variables, indexing; combine, abort)

Minimum and maximum of the hyperslab, skipping missing and non-finite
values; nothing when no finite value exists or the scan was aborted.
Several variables are read in lockstep -- the same hyperslab out of each
-- and every element is reduced to one number by `combine` before it
enters the range, so a vector plot pins |V| instead of one signed
component. The read is chunked along the hyperslab's last whole
dimension, and `abort` is polled between chunks.
"""
function hyperslab_extrema(
    dataset::Data.CDFDataset,
    variables::Vector{String},
    indexing::Vector{Union{Colon, Int}};
    combine::Function = scan_value,
    abort::Function = () -> false,
)::Union{Nothing, NTuple{2, Float64}}
    isempty(variables) && return nothing
    vars = [dataset.ds[name] for name in variables]
    sz = size(vars[1])
    length(sz) == length(indexing) || return nothing
    # components are sliced with one indexing, so they must share a shape
    all(v -> size(v) == sz, vars) || return nothing
    cpos = findlast(i -> i isa Colon, indexing)
    if cpos === nothing
        ranges = UnitRange{Int}[1:1]  # fully fixed: a single value
    else
        elements_per_step = 1
        for i in eachindex(indexing)
            i != cpos && indexing[i] isa Colon && (elements_per_step *= sz[i])
        end
        # the chunk budget covers all components together
        step = clamp(CHUNK_ELEMENTS ÷ (elements_per_step * length(vars)),
                     1, sz[cpos])
        ranges = [start:min(start + step - 1, sz[cpos])
                  for start in 1:step:sz[cpos]]
    end
    lo, hi = Inf, -Inf
    buffer = Vector{Float64}(undef, length(vars))
    for r in ranges
        abort() && return nothing
        idx = cpos === nothing ? collect(Any, indexing) :
            Any[i == cpos ? r : indexing[i] for i in eachindex(indexing)]
        chunks = map(var -> begin
            chunk = var[idx...]
            chunk isa AbstractArray ? chunk : [chunk]
        end, vars)
        all(c -> length(c) == length(chunks[1]), chunks) || return nothing
        for k in eachindex(chunks[1])
            usable = true
            for (n, chunk) in enumerate(chunks)
                v = chunk[k]
                if v === missing || !(v isa Number) || !isfinite(v)
                    usable = false
                    break
                end
                buffer[n] = Float64(v)
            end
            usable || continue
            x = apply_combine(combine, buffer)
            isfinite(x) || continue
            x < lo && (lo = x)
            x > hi && (hi = x)
        end
        yield()
    end
    lo > hi ? nothing : (lo, hi)
end

hyperslab_extrema(dataset::Data.CDFDataset, variable::String,
                  indexing::Vector{Union{Colon, Int}};
                  combine::Function = scan_value,
                  abort::Function = () -> false) =
    hyperslab_extrema(dataset, [variable], indexing;
                      combine = combine, abort = abort)

end
