using DataStructures
using NCDatasets

using CDFViewer.Data
using CDFViewer.Parsing
using CDFViewer.UI
using CDFViewer.Plotting

"""
    set_kwargs!(fd, kw_str)

Apply a keyword line the way the prompt does: parse it, then hand the
values to the store.
"""
set_kwargs!(fd::Plotting.FigureData, kw_str::AbstractString)::Nothing =
    Plotting.update_kwargs!(fd, Parsing.parse_kwargs(kw_str))

struct Dim
    name::String
    values::Any
    attrib::OrderedDict{String, Any}
end

DIM_DICT = OrderedDict(dim.name => dim for dim in [
    Dim("lon", collect(1:5), OrderedDict()),
    Dim("lat", collect(1:7), OrderedDict()),
    Dim("time", collect(1:4), OrderedDict("units" => "days since 1951-1-1 00:00:00")),
    Dim("string_dim", ["a", "ab", "abc"], OrderedDict()),
    Dim("float_dim", collect(1.0:0.2:2.0), OrderedDict()),
    Dim("only_unit", collect(1:3), OrderedDict("units" => "n/a")),
    Dim("only_long", collect(1:4), OrderedDict("long_name" => "Long")),
    Dim("both_atts", collect(1:6), OrderedDict(
        "units" => "m/s",
        "long_name" => "Both"
    )),
    Dim("extra_attr", collect(1:2), OrderedDict("extra" => "attr")),
])

struct Var
    name::String
    dims::Vector{String}
    attrib::OrderedDict{String, Any}
    dtype::DataType
end

VAR_DICT = OrderedDict(var.name => var for var in [
    Var("1d_float", ["lon"], OrderedDict(), Float64),
    Var("2d_float", ["lon", "lat"], OrderedDict(), Float64),
    Var("3d_float", ["lon", "lat", "time"], OrderedDict(), Float64),
    Var("4d_float", ["lon", "lat", "time", "float_dim"], OrderedDict(), Float64),
    Var("5d_float", ["lon", "lat", "float_dim", "only_unit", "only_long"], OrderedDict(), Float64),
    Var("2d_gap", ["lon", "float_dim"], OrderedDict(), Float64),
    Var("2d_gap_inv", ["float_dim", "lon"], OrderedDict(), Float64),
    Var("int_var", ["lon", "lat"], OrderedDict(), Int64),
    Var("string_var", ["string_dim"], OrderedDict(), String),
    Var("only_unit_var", ["lon"], OrderedDict("units" => "n/a"), Float64),
    Var("only_long_var", ["lat"], OrderedDict("long_name" => "Long"), Float64),
    Var("both_atts_var", ["lon"], OrderedDict(
        "units" => "m/s",
        "long_name" => "Both"
    ), Float64),
    Var("extra_attr_var", ["lon"], OrderedDict("extra" => "attr"), Float64),
])

function get_dims(var::String)
    if haskey(VAR_DICT, var)
        return VAR_DICT[var].dims
    else
        return String[]
    end
end

function init_temp_dataset()::String
    file = tempname() * ".nc"

    NCDataset(file,"c",attrib = OrderedDict("title" => "this is a test file")) do ds
        for dim in values(DIM_DICT)
            defVar(ds, dim.name, dim.values, (dim.name,), attrib = dim.attrib)
        end
        for var in values(VAR_DICT)
            size = map(dim -> length(DIM_DICT[dim].values), var.dims)
            if var.dtype == String
                data = [join(rand('a':'z', rand(1:5))) for _ in 1:prod(size)]
                if length(size) > 1
                    data = reshape(data, size)
                end
            else
                data = rand(var.dtype, size...)
            end
            defVar(ds, var.name, data, var.dims, attrib = var.attrib)
        end
        defVar(ds, "untaken_dim", collect(1:4), ("untaken",), attrib = OrderedDict())
    end

    file
end

function make_temp_dataset()
    Data.CDFDataset([init_temp_dataset()])
end

# ========================================
#  Vector Components
# ========================================
# A lon/lat/time file with wind components, for the vector plot types:
# `u`/`v` are the pair, `uas`/`vas` and `U10`/`V10` exercise the name
# guessing, `uodd` has no partner at all and `umix` only one over the
# wrong dimensions. Every field is deterministic, so a test can compute
# the true |V| range from the file.

VECTOR_LON = collect(range(-180.0, 150.0, 12))
VECTOR_LAT = collect(range(-70.0, 70.0, 8))
VECTOR_TIME = collect(1.0:3.0)

# `u` deliberately changes sign, so its own range is nothing like |V|'s
vector_u(lon, lat, time) =
    [12.0 * sind(2la) - 4.0 * sind(2lo) + 0.5t
     for lo in lon, la in lat, t in time]
vector_v(lon, lat, time) =
    [6.0 * cosd(lo) * cosd(la) - 0.3t for lo in lon, la in lat, t in time]

function init_vector_temp_dataset()::String
    file = tempname() * ".nc"
    lon, lat, time = VECTOR_LON, VECTOR_LAT, VECTOR_TIME
    u = vector_u(lon, lat, time)
    v = vector_v(lon, lat, time)

    NCDataset(file, "c", attrib = OrderedDict(
            "title" => "this is a test file with wind components")) do ds
        defVar(ds, "lon", lon, ("lon",), attrib = OrderedDict(
            "standard_name" => "longitude", "units" => "degrees_east"))
        defVar(ds, "lat", lat, ("lat",), attrib = OrderedDict(
            "standard_name" => "latitude", "units" => "degrees_north"))
        defVar(ds, "time", time, ("time",), attrib = OrderedDict(
            "units" => "days since 2000-01-01 00:00:00"))

        dims = ("lon", "lat", "time")
        defVar(ds, "u", u, dims, attrib = OrderedDict(
            "units" => "m s-1", "long_name" => "Eastward wind"))
        defVar(ds, "v", v, dims, attrib = OrderedDict(
            "units" => "m s-1", "long_name" => "Northward wind"))
        defVar(ds, "uas", 0.5 .* u, dims, attrib = OrderedDict("units" => "m s-1"))
        defVar(ds, "vas", 0.5 .* v, dims, attrib = OrderedDict("units" => "m s-1"))
        defVar(ds, "U10", 2.0 .* u, dims, attrib = OrderedDict("units" => "m s-1"))
        defVar(ds, "V10", 2.0 .* v, dims, attrib = OrderedDict("units" => "m s-1"))
        defVar(ds, "temp", abs.(u), dims, attrib = OrderedDict("units" => "K"))
        # a pair whose unit is the CF spelling of "dimensionless"
        defVar(ds, "ufrac", 0.1 .* u, dims, attrib = OrderedDict(
            "units" => "1", "long_name" => "Zonal fraction"))
        defVar(ds, "vfrac", 0.1 .* v, dims, attrib = OrderedDict(
            "units" => "1", "long_name" => "Meridional fraction"))
        # a u-named variable whose partner does not exist
        defVar(ds, "uodd", u[:, :, 1], ("lon", "lat"),
               attrib = OrderedDict("units" => "m s-1"))
        # a pair whose dimensions disagree
        defVar(ds, "umix", u, dims, attrib = OrderedDict("units" => "m s-1"))
        defVar(ds, "vmix", v[:, :, 1], ("lon", "lat"),
               attrib = OrderedDict("units" => "m s-1"))
    end

    file
end

make_vector_temp_dataset() = Data.CDFDataset([init_vector_temp_dataset()])

"The true |V| range of the whole `u`/`v` field of the vector fixture."
function vector_magnitude_range(dataset::Data.CDFDataset)
    u = dataset.ds["u"][:, :, :]
    v = dataset.ds["v"][:, :, :]
    extrema(hypot.(u, v))
end

# ========================================
#  Vertical section
# ========================================
# The anisotropic case: 45 km along `y`, 150 m down `z`, so the two axes
# are drawn at pixel scales two orders of magnitude apart. `v` is a
# surface jet flowing toward +y and `w` is zero, which makes the arrows
# horizontal and their drawn length easy to read off.

SECTION_Y = collect(range(234.375, 44765.625, 96))
SECTION_Z = -150.0 .+ ((0:47) .+ 0.5) .* 150.0 ./ 48
SECTION_TIME = collect(0.0:2.0)

function init_section_temp_dataset()::String
    file = tempname() * ".nc"
    y, z, time = SECTION_Y, SECTION_Z, SECTION_TIME
    b = [1e-4 * zz for _ in time, _ in y, zz in z]
    v = [0.1 * exp(zz / 10.0) for _ in time, _ in y, zz in z]
    w = zeros(length(time), length(y), length(z))

    NCDataset(file, "c") do ds
        defVar(ds, "time", time, ("time",), attrib = OrderedDict(
            "units" => "days since 2000-01-01 00:00:00"))
        defVar(ds, "y", y, ("y",), attrib = OrderedDict("units" => "m"))
        defVar(ds, "z", z, ("z",), attrib = OrderedDict("units" => "m"))

        dims = ("time", "y", "z")
        defVar(ds, "b", b, dims, attrib = OrderedDict(
            "units" => "m/s^2", "long_name" => "Total buoyancy"))
        defVar(ds, "v", v, dims, attrib = OrderedDict(
            "units" => "m/s", "long_name" => "Offshore velocity"))
        defVar(ds, "w", w, dims, attrib = OrderedDict(
            "units" => "m/s", "long_name" => "Vertical velocity"))
    end

    file
end

make_section_temp_dataset() = Data.CDFDataset([init_section_temp_dataset()])

# ========================================
#  Unstructured Data
# ========================================

function init_unstructured_temp_dataset()::String
    file = tempname() * ".nc"

    ntime = 5
    ncells = 100
    nvertices = 120
    nlevels = 10

    NCDataset(file,"c",attrib = OrderedDict("title" => "this is a test file with unstructured data")) do ds
        # Coordinates
        defVar(ds, "time", collect(1:ntime), ("time",), attrib = OrderedDict(
            "standard_name" => "time",
            "calendar" => "gregorian",
            "axis" => "T",
            "units" => "minutes since 2000-1-1 00:00:00"))
        defVar(ds, "clon", rand(ncells) * 2π .- π, ("ncells",), attrib = OrderedDict(
            "standard_name" => "longitude",
            "long_name" => "center longitude",
            "units" => "radian"))
        defVar(ds, "clat", rand(ncells) * π .- π/2, ("ncells",), attrib = OrderedDict(
            "standard_name" => "latitude",
            "long_name" => "center latitude",
            "units" => "radian"))
        defVar(ds, "vlon", rand(nvertices) * 2π .- π, ("nvertices",), attrib = OrderedDict(
            "standard_name" => "longitude",
            "long_name" => "vertex longitude",
            "units" => "radian"))
        defVar(ds, "vlat", rand(nvertices) * π .- π/2, ("nvertices",), attrib = OrderedDict(
            "standard_name" => "latitude",
            "long_name" => "vertex latitude",
            "units" => "radian"))
        defVar(ds, "depth", LinRange(0, 5000, nlevels), ("depth",), attrib = OrderedDict(
            "standard_name" => "depth",
            "long_name" => "depth_below_sea",
            "units" => "m",
            "positive" => "down",
            "axis" => "Z"))
        # Variables
        defVar(ds, "zos", rand(ntime, ncells), ("time", "ncells"), attrib = OrderedDict(
            "standard_name" => "zos.TL3",
            "units" => "m",
            "coordinates" => "clat clon"))
        defVar(ds, "u", rand(ntime, nlevels, ncells), ("time", "depth", "ncells"), attrib = OrderedDict(
            "standard_name" => "sea_water_x_velocity",
            "long_name" => "u zonal velocity component",
            "units" => "m s-1",
            "coordinates" => "clat clon"))
        defVar(ds, "v", rand(ntime, nlevels, ncells), ("time", "depth", "ncells"), attrib = OrderedDict(
            "standard_name" => "sea_water_y_velocity",
            "long_name" => "v meridional velocity component",
            "units" => "m s-1",
            "coordinates" => "clat clon"))
        defVar(ds, "vort", rand(ntime, nlevels, nvertices), ("time", "depth", "nvertices"), attrib = OrderedDict(
            "standard_name" => "vort",
            "long_name" => "vorticity",
            "units" => "s-1",
            "coordinates" => "vlat vlon"))
    end

    file
end

function make_unstructured_temp_dataset()
    Data.CDFDataset([init_unstructured_temp_dataset()])
end

function init_semi_unstructured_temp_dataset()::String
    file = tempname() * ".nc"

    nx = 10
    ny = 15
    ntime = 5

    x = LinRange(10, 90, nx)  # Radius
    y = LinRange(0, 2π, ny)  # Angle

    lon = x .* cos.(y')
    lat = x .* sin.(y')

    NCDataset(file,"c",attrib = OrderedDict("title" => "this is a test file with semi-unstructured data")) do ds
        # Coordinates
        defVar(ds, "time", collect(1:ntime), ("time",), attrib = OrderedDict(
            "standard_name" => "time",
            "calendar" => "gregorian",
            "axis" => "T",
            "units" => "minutes since 2000-1-1 00:00:00"))
        defVar(ds, "lon", lon, ("x", "y"), attrib = OrderedDict(
            "standard_name" => "longitude",
            "long_name" => "longitude",
            "units" => "degrees"))
        defVar(ds, "lat", lat, ("x", "y"), attrib = OrderedDict(
            "standard_name" => "latitude",
            "long_name" => "latitude",
            "units" => "degrees"))
        # Variables
        defVar(ds, "temp", rand(ntime, nx, ny), ("time", "x", "y"), attrib = OrderedDict(
            "standard_name" => "sea_water_temperature",
            "long_name" => "sea water temperature",
            "units" => "degC",
            "coordinates" => "lon lat"))
        defVar(ds, "salt", rand(ntime, nx, ny), ("time", "x", "y"), attrib = OrderedDict(
            "standard_name" => "sea_water_salinity",
            "long_name" => "sea water salinity",
            "units" => "psu",
            "coordinates" => "lon lat"))
        defVar(ds, "mask", rand(0:1, nx, ny), ("x", "y"), attrib = OrderedDict(
            "long_name" => "land-sea mask",
            "flag_values" => "0, 1",
            "flag_meanings" => "land sea",
            "coordinates" => "lon lat"))
    end

    file
end

make_semi_unstructured_temp_dataset() = Data.CDFDataset([init_semi_unstructured_temp_dataset()])

# ========================================
#  Dimensionless Units
# ========================================
# Every spelling that must print no unit at all, next to look-alikes that
# must keep printing ("1e-3", "s-1", "%").

function init_dimensionless_temp_dataset()::String
    file = tempname() * ".nc"

    NCDataset(file, "c") do ds
        defVar(ds, "one", collect(1.0:5.0), ("one",), attrib = OrderedDict(
            "units" => "1", "long_name" => "Ratio"))
        defVar(ds, "spelled", collect(1.0:3.0), ("spelled",),
            attrib = OrderedDict("units" => " Dimensionless "))
        defVar(ds, "dash", collect(1.0:3.0), ("dash",), attrib = OrderedDict(
            "units" => "-"))
        defVar(ds, "nothing", collect(1.0:3.0), ("nothing",),
            attrib = OrderedDict("units" => "NONE"))
        defVar(ds, "blank", collect(1.0:3.0), ("blank",), attrib = OrderedDict(
            "units" => "  "))
        defVar(ds, "milli", collect(1.0:3.0), ("milli",), attrib = OrderedDict(
            "units" => "1e-3"))
        defVar(ds, "rate", collect(1.0:3.0), ("rate",), attrib = OrderedDict(
            "units" => "s-1"))
        defVar(ds, "frac", rand(5, 3), ("one", "milli"), attrib = OrderedDict(
            "units" => "1", "long_name" => "Cloud fraction"))
        defVar(ds, "pct", rand(5, 3), ("one", "milli"), attrib = OrderedDict(
            "units" => "%"))
    end

    file
end

make_dimensionless_temp_dataset() = Data.CDFDataset([init_dimensionless_temp_dataset()])
