using Test
using CDFViewer.Data
using GLMakie

# ============================================================
#  SETUP TEST DATA
# ============================================================


@testset "Data.jl" begin
    # open dataset
    dataset = make_temp_dataset()

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

    # check variable dimensions
    @test Data.get_var_dims(dataset, "1d_float") == ["lon"]
    @test Data.get_var_dims(dataset, "2d_float") == ["lon", "lat"]
    @test Data.get_var_dims(dataset, "2d_gap") == ["lon", "float_dim"]
    @test Data.get_var_dims(dataset, "2d_gap_inv") == ["float_dim", "lon"]

    # check data dimension observables
    test_dim = Observable("lon")
    update_switch = Observable(true)
    dim_array = Data.get_dim_array(dataset, test_dim, update_switch)
    @test dim_array isa Observable{Vector{Float64}}
    for dim in dataset.dimensions
        test_dim[] = dim
        @test dim_array isa Observable{Vector{Float64}}
        @test length(dim_array[]) == dataset.ds.dim[dim]
    end
    # check the Not-Selected option
    test_dim[] = "Not Selected"
    @test dim_array[] == Float64[]

    # check the update switch
    update_switch[] = false
    test_dim[] = "lon"
    @test dim_array[] == Float64[]
    update_switch[] = true
    @test length(dim_array[]) == dataset.ds.dim["lon"]

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
