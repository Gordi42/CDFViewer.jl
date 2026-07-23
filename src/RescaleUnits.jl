module RescaleUnits

using DataStructures
using NCDatasets
using NCDatasets.CommonDataModel: AbstractDataset

# ======================================================
#  Unit Mappings
# ======================================================

struct UnitMapping
    from_unit::String
    to_unit::String
    scale_function::Function
end

function radians_to_degrees(x)
    x * (180.0 / π)
end

const unit_mappings = OrderedDict{String, UnitMapping}(
    "rad2deg" => UnitMapping("radian", "degrees", radians_to_degrees),
)

# ======================================================
#  
# ======================================================

struct CoordinateUnitMapping
    coord::String
    unit_mapping::UnitMapping
end

const coordinate_unit_mappings = OrderedDict{String, CoordinateUnitMapping}(
    "longitude" => CoordinateUnitMapping("longitude", unit_mappings["rad2deg"]),
    "latitude" => CoordinateUnitMapping("latitude", unit_mappings["rad2deg"]),
)

function get_standard_name(coord::String, ds::AbstractDataset)::String
    !haskey(ds, coord) && return lowercase(coord)
    name_variants = [lowercase(coord)]
    if haskey(ds.attrib, "standard_name")
        push!(name_variants, lowercase(ds.attrib["standard_name"]))
    end
    if haskey(ds.attrib, "long_name")
        push!(name_variants, lowercase(ds.attrib["long_name"]))
    end
    # check if any of the name_variants matches "lon" or "longitude"
    for name in name_variants
        if occursin("lon", name) || occursin("longitude", name)
            return "longitude"
        elseif occursin("lat", name) || occursin("latitude", name)
            return "latitude"
        end
    end
    if haskey(ds.attrib, "standard_name")
        return lowercase(ds.attrib["standard_name"])
    end
    return lowercase(coord)
end

function get_unit(ds::AbstractDataset, coord::String)::String
    !haskey(ds, coord) && return ""
    !haskey(ds[coord].attrib, "units") && return ""
    return lowercase(ds[coord].attrib["units"])
end

function get_remapped_unit(ds::AbstractDataset, coord::String)::String
    unit = get_unit(ds, coord)
    standard_name = get_standard_name(coord, ds)
    if standard_name in keys(coordinate_unit_mappings)
        mapping = coordinate_unit_mappings[standard_name]
        if unit == mapping.unit_mapping.from_unit
            return mapping.unit_mapping.to_unit
        end
    end
    unit
end

function get_transformation_function(ds::AbstractDataset, coord::String)::Function
    unit = get_unit(ds, coord)
    standard_name = get_standard_name(coord, ds)
    if standard_name in keys(coordinate_unit_mappings)
        mapping = coordinate_unit_mappings[standard_name]
        if unit == mapping.unit_mapping.from_unit
            return mapping.unit_mapping.scale_function
        end
    end
    identity  # no transformation
end

# ======================================================
#  Display units
# ======================================================
#
# Families of linearly related units used to *render* an axis in a
# different unit (e.g. meters shown as km) without touching the data.
# Conversion is only allowed within a family; every factor maps a unit
# to the family's base unit. Only pure scale factors belong here --
# offset conversions (Celsius/Kelvin) would break round tick values.

struct DisplayUnit
    family::Symbol
    factor::Float64    # value in this unit * factor == value in base unit
    canonical::String  # spelling used in axis labels
end

const display_units = Dict{String, DisplayUnit}()

function register_display_unit!(family::Symbol, factor::Float64,
                                canonical::String, spellings::String...)
    for spelling in (canonical, spellings...)
        display_units[lowercase(spelling)] = DisplayUnit(family, factor, canonical)
    end
end

register_display_unit!(:length, 1e-3, "mm",
    "millimeter", "millimeters", "millimetre", "millimetres")
register_display_unit!(:length, 1e-2, "cm",
    "centimeter", "centimeters", "centimetre", "centimetres")
register_display_unit!(:length, 1.0, "m", "meter", "meters", "metre", "metres")
register_display_unit!(:length, 1e3, "km",
    "kilometer", "kilometers", "kilometre", "kilometres")
register_display_unit!(:time, 1.0, "s", "sec", "second", "seconds")
register_display_unit!(:time, 60.0, "min", "minute", "minutes")
register_display_unit!(:time, 3600.0, "h", "hr", "hour", "hours")
register_display_unit!(:time, 86400.0, "d", "day", "days")
register_display_unit!(:pressure, 1.0, "Pa", "pascal")
register_display_unit!(:pressure, 100.0, "hPa")
register_display_unit!(:pressure, 100.0, "mbar", "millibar")
register_display_unit!(:pressure, 1000.0, "kPa")
register_display_unit!(:pressure, 1e4, "dbar")
register_display_unit!(:pressure, 1e5, "bar")

"The DisplayUnit for a unit spelling, or nothing if unknown."
function display_unit(unit::AbstractString)::Union{DisplayUnit, Nothing}
    get(display_units, lowercase(strip(unit)), nothing)
end

"All canonical display-unit spellings, grouped by family."
function display_unit_names()::Vector{String}
    units = unique(values(display_units))
    sort!(units, by = u -> (u.family, u.factor))
    unique(u.canonical for u in units)
end

"""
Multiplier taking values in unit `from` to values displayed in unit `to`,
or nothing when the units are unknown or from different families.
"""
function display_factor(from::AbstractString,
                        to::AbstractString)::Union{Float64, Nothing}
    from_unit = display_unit(from)
    to_unit = display_unit(to)
    (from_unit === nothing || to_unit === nothing) && return nothing
    from_unit.family === to_unit.family || return nothing
    from_unit.factor / to_unit.factor
end

end
