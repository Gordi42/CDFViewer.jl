module RescaleUnits

using DataStructures
using NCDatasets

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

function get_standard_name(coord::String, ds::NCDataset)::String
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

function get_unit(ds::NCDataset, coord::String)::String
    !haskey(ds, coord) && return ""
    !haskey(ds[coord].attrib, "units") && return ""
    return lowercase(ds[coord].attrib["units"])
end

function get_remapped_unit(ds::NCDataset, coord::String)::String
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

function get_transformation_function(ds::NCDataset, coord::String)::Function
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

end
