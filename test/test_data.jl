using Test
using CDFViewer.Constants
using CDFViewer.Data
using GLMakie

@testset "Data.jl" begin

    @testset "Structure" begin
        # Arange
        dataset = make_temp_dataset()

        # Assert
        @test dataset isa Data.CDFDataset
        @test setdiff(dataset.dimensions, keys(DIM_DICT))[1] == "untaken"
        @test setdiff(dataset.variables, keys(VAR_DICT))[1] == "untaken_dim"
    end

    @testset "Variable Dimensions" begin
        # Arange
        dataset = make_temp_dataset()

        # Assert
        @test Data.get_var_dims(dataset, "1d_float") == ["lon"]
        @test Data.get_var_dims(dataset, "2d_float") == ["lon", "lat"]
        @test Data.get_var_dims(dataset, "2d_gap") == ["lon", "float_dim"]
        @test Data.get_var_dims(dataset, "2d_gap_inv") == ["float_dim", "lon"]
    end

    @testset "Labels" begin
        # Arange
        dataset = make_temp_dataset()

        # Assert
        @test Data.get_label(dataset, "lon") == "lon"
        @test Data.get_label(dataset, "only_unit") == "only_unit [n/a]"
        @test Data.get_label(dataset, "only_long") == "Long"
        @test Data.get_label(dataset, "both_atts") == "Both [m/s]"
        @test Data.get_label(dataset, "untaken") == "untaken"
        @test Data.get_label(dataset, "both_atts_var") == "Both [m/s]"
    end

    @testset "Dimension Value Labels" begin
        # Arange
        dataset = make_temp_dataset()

        # Assert
        @test Data.get_dim_value_label(dataset, "lon", 2) == "  → lon: 2"
        @test Data.get_dim_value_label(dataset, "only_unit", 1) == "  → only_unit: 1 n/a"
        @test Data.get_dim_value_label(dataset, "only_long", 2) == "  → Long: 2"
        @test Data.get_dim_value_label(dataset, "both_atts", 3) == "  → Both: 3 m/s"
        @test Data.get_dim_value_label(dataset, "string_dim", 2) == "  → string_dim: ab"
        @test Data.get_dim_value_label(dataset, "float_dim", 4) == "  → float_dim: 1.6"
        @test Data.get_dim_value_label(dataset, "time", 2) == "  → time: 1951-01-03 00:00:00"
        @test Data.get_dim_value_label(dataset, "untaken", 2) == "  → untaken: 2"
        @test Data.get_dim_value_label(dataset, Constants.NOT_SELECTED_LABEL, 1) == "  → No dimension selected"
        @test Data.get_dim_value_label(dataset, "lon", 10) == "  → lon: Index 10 out of bounds"
    end

    @testset "Dimension Observables" begin
        # Arange
        dataset = make_temp_dataset()
        # create the dimension observable
        test_dim = Observable("lon")
        update_switch = Observable(true)
        
        # Act
        dim_array = Data.get_dim_array(dataset, test_dim, update_switch)

        # Assert
        @test dim_array isa Observable{Vector{Float64}}
        for dim in dataset.dimensions
            test_dim[] = dim
            @test dim_array isa Observable{Vector{Float64}}
            @test length(dim_array[]) == dataset.ds.dim[dim]
        end

        # Act:
        test_dim[] = Constants.NOT_SELECTED_LABEL

        # Assert
        @test dim_array[] == Float64[1]

        # Act: (turn off updates)
        update_switch[] = false
        test_dim[] = "lon"

        # Assert: (should not update)
        @test dim_array[] == Float64[1]

        # Act: (turn on updates)
        update_switch[] = true

        # Assert: (should update)
        @test length(dim_array[]) == dataset.ds.dim["lon"]
    end

    @testset "Data Slicing" begin
        # Arange
        dataset = make_temp_dataset()
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

        # Act: (get the dimensions of the variable)
        sl = (var, plot_dims) -> Data.get_data_slice(
            collect(dimnames(dataset.ds[var])), plot_dims, dimension_selections)

        # Assert
        @test sl("1d_float", ["lon"]) == [Colon()]
        @test sl("2d_float", ["lon"]) == [Colon(), 3]
        @test sl("2d_float", ["lon", "lat"]) == [Colon(), Colon()]
        @test sl("2d_gap", ["lon"]) == [Colon(), 4]
        @test sl("2d_gap_inv", ["lon"]) == [4, Colon()]
        @test sl("5d_float", ["lat", "only_long"]) == [2, Colon(), 4, 1, Colon()]
        @test sl("5d_float", ["float_dim", "lat", "lon"]) == [Colon(), Colon(), Colon(), 1, 2]
        @test sl("string_var", ["string_dim"]) == [Colon()]
        @test sl("untaken_dim", ["untaken"]) == [Colon()]
    end

    @testset "Data Extraction" begin
        # Arange
        dataset = make_temp_dataset()
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

        # Act: (get the data shape)
        gdata_shape = (var, plot_dims) -> Data.get_data(dataset, var, plot_dims, dimension_selections).size

        # Assert
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

end
