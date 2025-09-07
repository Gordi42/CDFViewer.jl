using DataStructures
using NCDatasets

using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting

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


function make_temp_dataset()

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

    Data.CDFDataset(file)
end

function make_ui(dataset::Data.CDFDataset)
    fig = Plotting.create_figure()
    ui = UI.UIElements(fig, dataset)
    fig, ui
end
