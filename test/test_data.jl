using Test
using CDFViewer.Data
using NCDatasets
using DataStructures
using GLMakie

import CDFViewer.Data as Data

# ============================================================
#  SETUP TEST DATA
# ============================================================

struct Dim
    name::String
    values::Any
    attrib::OrderedDict{String, Any}
end

const DIM_DICT = OrderedDict(dim.name => dim for dim in [
    Dim("lon", collect(1:5), OrderedDict()),
    Dim("lat", collect(1:7), OrderedDict()),
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

const VAR_DICT = OrderedDict(var.name => var for var in [
    Var("1d_float", ["lon"], OrderedDict(), Float64),
    Var("2d_float", ["lon", "lat"], OrderedDict(), Float64),
    Var("3d_float", ["lon", "lat", "float_dim"], OrderedDict(), Float64),
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
                data = zeros(var.dtype, size...)
            end
            defVar(ds, var.name, data, var.dims, attrib = var.attrib)
        end
        defVar(ds, "untaken_dim", collect(1:4), ("untaken",), attrib = OrderedDict())
    end

    return file
end

@testset "Data.jl" begin
    file = make_temp_dataset()
    # check that the file was created
    @test isfile(file)

    # open dataset
    dataset = Data.open_dataset(file)

    # check structure
    @test dataset isa Data.CDFDataset
    @test setdiff(dataset.dimensions, keys(DIM_DICT))[1] == "untaken"
    @test setdiff(dataset.variables, keys(VAR_DICT))[1] == "untaken_dim"

    # check labels
    @test Data.get_label(dataset, "lon") == "lon"
    @test Data.get_label(dataset, "only_unit") == "only_unit [n/a]"
    @test Data.get_label(dataset, "only_long") == "Long"
    @test Data.get_label(dataset, "both_atts") == "Both [m/s]"
    @test Data.get_label(dataset, "untaken") == "untaken"
    @test Data.get_label(dataset, "both_atts_var") == "Both [m/s]"

    # check data dimension observables
    test_dim = Observable("lon")
    dim_array = Data.get_dim_array(dataset, test_dim)
    @test dim_array isa Observable{Vector{Float64}}
    for dim in dataset.dimensions
        test_dim[] = dim
        @test dim_array isa Observable{Vector{Float64}}
        @test length(dim_array[]) == dataset.ds.dim[dim]
    end
    # check the Not-Selected option
    test_dim[] = "Not Selected"
    @test dim_array[] == Float64[]

    # check slice function
    dimension_selections = Dict(
        "lon" => 2,
        "lat" => 3,
        "string_dim" => 2,
        "float_dim" => 4,
        "only_unit" => 1,
        "only_long" => 2,
        "both_atts" => 3,
        "extra_attr" => 1,
        "untaken" => 2,
    )

    # get the dimensions of the variable
    sl = (var, plot_dims) -> Data.get_data_slice(
        collect(dimnames(dataset.ds[var])), plot_dims, dimension_selections)

    @test sl("1d_float", ["lon"]) == [Colon()]
    @test sl("2d_float", ["lon"]) == [Colon(), 3]
    @test sl("2d_float", ["lon", "lat"]) == [Colon(), Colon()]
    @test sl("2d_gap", ["lon"]) == [Colon(), 4]
    @test sl("2d_gap_inv", ["lon"]) == [4, Colon()]
    @test sl("5d_float", ["lat", "only_long"]) == [2, Colon(), 4, 1, Colon()]
    @test sl("5d_float", ["float_dim", "lat", "lon"]) == [Colon(), Colon(), Colon(), 1, 2]
    @test sl("string_var", ["string_dim"]) == [Colon()]
    @test sl("untaken_dim", ["untaken"]) == [Colon()]

    # Check data extraction
    gdata_shape = (var, plot_dims) -> Data.get_data(dataset, var, plot_dims, dimension_selections).size

    @test gdata_shape("1d_float", ["lon"]) == (5,)
    @test gdata_shape("2d_float", ["lon"]) == (5,)
    @test gdata_shape("2d_float", ["lon", "lat"]) == (5, 7)
    @test gdata_shape("2d_float", ["lat", "lon"]) == (7, 5)
    @test gdata_shape("2d_gap", ["lon"]) == (5,)
    @test gdata_shape("2d_gap_inv", ["lon"]) == (5,)
    @test gdata_shape("2d_gap", ["lon", "float_dim"]) == (5, 6)
    @test gdata_shape("2d_gap_inv", ["lon", "float_dim"]) == (5, 6)
    @test gdata_shape("5d_float", ["lat", "only_long"]) == (7, 4)
    @test gdata_shape("int_var", ["lat"]) == (7,)
    @test gdata_shape("string_var", ["string_dim"]) == (3,)
    @test gdata_shape("untaken_dim", ["untaken"]) == (4,) 
end
