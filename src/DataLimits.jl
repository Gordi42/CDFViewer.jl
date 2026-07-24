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
    hyperslab_elements(dataset, variable, indexing)

Number of values the hyperslab covers -- known before reading a single
byte, so callers can decide whether a scan is affordable.
"""
function hyperslab_elements(
    dataset::Data.CDFDataset,
    variable::String,
    indexing::Vector{Union{Colon, Int}},
)::Int
    sz = size(dataset.ds[variable])
    length(sz) == length(indexing) || return 0
    n = 1
    for i in eachindex(indexing)
        indexing[i] isa Colon && (n *= sz[i])
    end
    n
end

"""
    hyperslab_extrema(dataset, variable, indexing; abort)

Minimum and maximum of the hyperslab, skipping missing and non-finite
values; nothing when no finite value exists or the scan was aborted.
The read is chunked along the hyperslab's last whole dimension, and
`abort` is polled between chunks.
"""
function hyperslab_extrema(
    dataset::Data.CDFDataset,
    variable::String,
    indexing::Vector{Union{Colon, Int}};
    abort::Function = () -> false,
)::Union{Nothing, NTuple{2, Float64}}
    var = dataset.ds[variable]
    sz = size(var)
    length(sz) == length(indexing) || return nothing
    cpos = findlast(i -> i isa Colon, indexing)
    if cpos === nothing
        ranges = UnitRange{Int}[1:1]  # fully fixed: a single value
    else
        elements_per_step = 1
        for i in eachindex(indexing)
            i != cpos && indexing[i] isa Colon && (elements_per_step *= sz[i])
        end
        step = clamp(CHUNK_ELEMENTS ÷ elements_per_step, 1, sz[cpos])
        ranges = [start:min(start + step - 1, sz[cpos])
                  for start in 1:step:sz[cpos]]
    end
    lo, hi = Inf, -Inf
    for r in ranges
        abort() && return nothing
        idx = cpos === nothing ? collect(Any, indexing) :
            Any[i == cpos ? r : indexing[i] for i in eachindex(indexing)]
        chunk = var[idx...]
        chunk isa AbstractArray || (chunk = [chunk])
        for v in chunk
            v === missing && continue
            v isa Number || continue
            isfinite(v) || continue
            x = Float64(v)
            x < lo && (lo = x)
            x > hi && (hi = x)
        end
        yield()
    end
    lo > hi ? nothing : (lo, hi)
end

end
