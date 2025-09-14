using Test
using CDFViewer.Constants
using CDFViewer.Data
using GLMakie

@testset "Data.jl" begin

    @testset "Structure" begin
        # Arrange
        dataset = make_temp_dataset()
        dataset.interp.group_map
        dataset.group_ids_of_var_dims

        # Assert
        @test dataset isa Data.CDFDataset
        @test setdiff(dataset.dimensions, keys(DIM_DICT))[1] == "untaken"
        @test setdiff(dataset.variables, keys(VAR_DICT))[1] == "untaken_dim"
    end

    @testset "Variable Coordinates" begin
        @testset "Regular Data" begin
            # Arrange
            dataset = make_temp_dataset()

            # Assert
            @test length(dataset.var_coords) == length(dataset.variables)
            @test dataset.var_coords["1d_float"] == ["lon"]
            @test dataset.var_coords["2d_float"] == ["lon", "lat"]
            @test dataset.var_coords["2d_gap"] == ["lon", "float_dim"]
            @test dataset.var_coords["2d_gap_inv"] == ["float_dim", "lon"]
            @test dataset.var_coords["5d_float"] == ["lon", "lat", "float_dim", "only_unit", "only_long"]
            @test dataset.var_coords["string_var"] == ["string_dim"]
            @test dataset.var_coords["untaken_dim"] == ["untaken"]
        end

        @testset "Unstructured Data" begin
            # Arrange
            dataset = make_unstructured_temp_dataset()

            # Assert
            @test length(dataset.var_coords) == length(dataset.variables)
            @test issetequal(
                dataset.coordinates,
                ["time", "clon", "clat", "vlon", "vlat", "depth"])
            @test issetequal(
                dataset.var_coords["zos"],
                ["time", "clon", "clat"])
            @test issetequal(
                dataset.var_coords["u"],
                ["time", "depth", "clon", "clat"])
            @test issetequal(
                dataset.var_coords["vort"],
                ["time", "depth", "vlon", "vlat"])
        end

        @testset "Semi Unstructured Data" begin
            # Arrange
            dataset = make_semi_unstructured_temp_dataset()

            # Assert
            @test length(dataset.var_coords) == length(dataset.variables)
            @test issetequal(
                dataset.coordinates,
                ["time", "lon", "lat"])
            @test issetequal(
                dataset.var_coords["temp"],
                ["time", "lon", "lat"])
            @test issetequal(
                dataset.var_coords["mask"],
                ["lon", "lat"])
        end
    end

    @testset "Group IDs of Variable Dimensions" begin
        @testset "Regular Data" begin
            # Arrange
            dataset = make_temp_dataset()
            g = dataset.interp.group_map
            gi = dataset.group_ids_of_var_dims

            # Assert
            @test length(dataset.group_ids_of_var_dims) == length(dataset.variables)
            @test gi["1d_float"] == [g["lon"]]
            @test gi["2d_float"] == [g["lon"], g["lat"]]
            @test gi["3d_float"] == [g["lon"], g["lat"], g["time"]]
            @test gi["4d_float"] == [g["lon"], g["lat"], g["time"], g["float_dim"]]
            @test gi["5d_float"] == [g["lon"], g["lat"], g["float_dim"], g["only_unit"], g["only_long"]]
            @test gi["2d_gap"] == [g["lon"], g["float_dim"]]
            @test gi["2d_gap_inv"] == [g["float_dim"], g["lon"]]
            @test gi["int_var"] == [g["lon"], g["lat"]]
            @test gi["string_var"] == [g["string_dim"]]
            @test gi["only_unit_var"] == [g["lon"]]
            @test gi["only_long_var"] == [g["lat"]]
            @test gi["both_atts_var"] == [g["lon"]]
            @test gi["extra_attr_var"] == [g["lon"]]
            @test gi["untaken_dim"] == [g["untaken"]]
        end

        @testset "Unstructured Data" begin
            # Arrange
            dataset = make_unstructured_temp_dataset()
            g = dataset.interp.group_map
            gi = dataset.group_ids_of_var_dims

            # Assert
            @test length(dataset.group_ids_of_var_dims) == length(dataset.variables)
            @test gi["zos"] == [g["time"], g["clat"]]
            @test gi["u"] == [g["time"], g["depth"], g["clon"]]
            @test gi["v"] == [g["time"], g["depth"], g["clat"]]
            @test gi["vort"] == [g["time"], g["depth"], g["vlon"]]
        end

        @testset "Semi Unstructured Data" begin
            # Arrange
            dataset = make_semi_unstructured_temp_dataset()
            g = dataset.interp.group_map
            gi = dataset.group_ids_of_var_dims

            # Assert
            @test length(dataset.group_ids_of_var_dims) == length(dataset.variables)
            @test g["lon"] == g["lon"]
            @test gi["temp"] == [g["time"], g["lon"], g["lat"]]
            @test gi["salt"] == [g["time"], g["lon"], g["lat"]]
            @test gi["mask"] == [g["lon"], g["lat"]]
        end
    end

    @testset "Paired Coordinates" begin
        @testset "Regular Data" begin
            # Arrange
            dataset = make_temp_dataset()

            # Assert: Regular data should have no paired coordinates
            for p_coords in values(dataset.paired_coords)
                @test isempty(p_coords)
            end
        end

        @testset "Unstructured Data" begin
            # Arrange
            dataset = make_unstructured_temp_dataset()

            # Assert
            @test length(dataset.paired_coords) == length(dataset.coordinates)
            @test issetequal(dataset.paired_coords["clon"], ["clat"])
            @test issetequal(dataset.paired_coords["clat"], ["clon"])
            @test issetequal(dataset.paired_coords["vlon"], ["vlat"])
            @test issetequal(dataset.paired_coords["vlat"], ["vlon"])
            @test isempty(dataset.paired_coords["time"])
            @test isempty(dataset.paired_coords["depth"])
        end

        @testset "Semi Unstructured Data" begin
            # Arrange
            dataset = make_semi_unstructured_temp_dataset()

            # Assert
            @test length(dataset.paired_coords) == length(dataset.coordinates)
            @test issetequal(dataset.paired_coords["lon"], ["lat"])
            @test issetequal(dataset.paired_coords["lat"], ["lon"])
            @test isempty(dataset.paired_coords["time"])
        end
    end

    @testset "Variable Dimensions" begin
        # Arrange
        dataset = make_temp_dataset()

        # Assert
        @test Data.get_var_dims(dataset, "1d_float") == ["lon"]
        @test Data.get_var_dims(dataset, "2d_float") == ["lon", "lat"]
        @test Data.get_var_dims(dataset, "2d_gap") == ["lon", "float_dim"]
        @test Data.get_var_dims(dataset, "2d_gap_inv") == ["float_dim", "lon"]
    end

    @testset "Labels" begin
        # Arrange
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
        # Arrange
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
        # Arrange
        dataset = make_temp_dataset()
        # create the dimension observable
        test_dim = Observable("lon")
        update_switch = Observable(true)
        
        # Act
        dim_array = Data.get_dim_array(dataset, test_dim, update_switch)

        # Assert
        @test dim_array isa Observable{Vector{Float64}}
        for dim in dataset.coordinates
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

    @testset "Indexing" begin
        @testset "Regular Data" begin
            # Arrange
            dataset = make_temp_dataset()
            interp = dataset.interp
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


            # Act: (get the indexing for the variable)
            idx = (var, plot_dims) -> Data.get_indexing(
                dataset.group_ids_of_var_dims[var],
                plot_dims, dimension_selections, interp)

            # Assert
            @test idx("1d_float", ["lon"]) == [Colon()]
            @test idx("2d_float", ["lon"]) == [Colon(), 3]
            @test idx("2d_float", ["lon", "lat"]) == [Colon(), Colon()]
            @test idx("2d_gap", ["lon"]) == [Colon(), 4]
            @test idx("2d_gap_inv", ["lon"]) == [4, Colon()]
            @test idx("5d_float", ["lat", "only_long"]) == [2, Colon(), 4, 1, Colon()]
            @test idx("5d_float", ["float_dim", "lat", "lon"]) == [Colon(), Colon(), Colon(), 1, 2]
            @test idx("string_var", ["string_dim"]) == [Colon()]
            @test idx("untaken_dim", ["untaken"]) == [Colon()]

            # Arrange: Change the ranges of some dimensions
            interp.rc.lat = 1:5
            interp.rc.float_dim = 2:6

            # Assert: (the indexing should update accordingly)
            @test idx("1d_float", ["lon"]) == [Colon()]
            @test idx("2d_float", ["lon"]) == [Colon(), Colon()]
            @test idx("2d_float", ["lon", "lat"]) == [Colon(), Colon()]
            @test idx("2d_gap", ["lon"]) == [Colon(), Colon()]
            @test idx("2d_gap_inv", ["lon"]) == [Colon(), Colon()]
            @test idx("5d_float", ["lat", "only_long"]) == [2, Colon(), Colon(), 1, Colon()]
            @test idx("5d_float", ["float_dim", "lat", "lon"]) == [Colon(), Colon(), Colon(), 1, 2]
            @test idx("string_var", ["string_dim"]) == [Colon()]
            @test idx("untaken_dim", ["untaken"]) == [Colon()]
        end

        @testset "Unstructured Data" begin
            # Arrange
            dataset = make_unstructured_temp_dataset()
            interp = dataset.interp
            dimension_selections = Dict(
                "time" => 2,
                "clon" => 3,
                "clat" => 4,
                "vlon" => 2,
                "vlat" => 3,
                "depth" => 1,
            )

            # Act: (get the indexing for the variable)
            idx = (var, plot_dims) -> Data.get_indexing(
                dataset.group_ids_of_var_dims[var],
                plot_dims, dimension_selections, interp)

            # Assert
            @test idx("zos", ["time"]) == [Colon(), Colon()]
            @test idx("zos", ["clon"]) == [2, Colon()]
            @test idx("zos", ["clat"]) == [2, Colon()]
            @test idx("u", ["clon", "depth"]) == [2, Colon(), Colon()]
            @test idx("v", ["clat", "time"]) == [Colon(), 1, Colon()]
            @test idx("vort", ["vlon", "depth"]) == [2, Colon(), Colon()]

            # Arrange: Change the ranges of some dimensions
            interp.rc.time = 2:5

            # Assert: (the indexing should update accordingly)
            @test idx("zos", ["clon"]) == [Colon(), Colon()]
        end

        @testset "Semi Unstructured Data" begin
            # Arrange
            dataset = make_semi_unstructured_temp_dataset()
            interp = dataset.interp
            dimension_selections = Dict(
                "time" => 2,
                "lon" => 3,
                "lat" => 4,
            )

            # Act: (get the indexing for the variable)
            idx = (var, plot_dims) -> Data.get_indexing(
                dataset.group_ids_of_var_dims[var],
                plot_dims, dimension_selections, interp)

            # Assert
            @test idx("temp", ["time"]) == [Colon(), Colon(), Colon()]
            @test idx("temp", ["lon"]) == [2, Colon(), Colon()]
            @test idx("temp", ["lat"]) == [2, Colon(), Colon()]
            @test idx("mask", ["lon"]) == [Colon(), Colon()]
            @test idx("mask", ["lat"]) == [Colon(), Colon()]

            # Arrange: Change the ranges of some dimensions
            interp.rc.time = 2:5

            # Assert: (the indexing should update accordingly)
            @test idx("temp", ["lon"]) == [Colon(), Colon(), Colon()]
        end
    end

    @testset "Reshaping" begin
        @testset "get_data_group_ids" begin
            # Arrange
            f = (group_ids, indexing) -> Data.get_data_group_ids(group_ids, Vector{Union{Colon, Int}}(indexing))
            C = Colon()

            # Assert
            @test f([1, 2, 3], [C, 2, C]) == [1, 3]
            @test f([1, 2, 3], [C, C, 3]) == [1, 2]
            @test f([1, 2, 3], [1, 2, 3]) == Int[]
            @test f([1, 2, 3], [C, C, C]) == [1, 2, 3]
            @test f([1, 2, 1, 4, 4], [C, 2, C, 1, C]) == [1, 1, 4]
        end

        @testset "compute_new_shape" begin
            # Arrange
            f = (data_shape, group_ids) -> Data.compute_new_shape(data_shape, group_ids)

            # Assert
            @test f((2, 4, 6), [1, 2, 3]) == (2, 4, 6)
            @test f((2, 4, 6), [1, 2, 1]) == (12, 4)
            @test f((2, 4, 6), [1, 2, 2]) == (2, 24)
            @test f((2, 4, 6), [1, 1, 1]) == (48,)
            @test f((2, 4, 6), [1, 1, 2]) == (8, 6)
            @test f((2, 3, 4, 5, 6, 7), [1, 2, 1, 3, 3, 2]) == (8, 21, 30)
        end

        @testset "get_permutation_to_group_dims" begin
            # Arrange
            f = (group_ids) -> Data.get_permutation_to_group_dims(group_ids)

            # Assert
            @test f([1, 2, 3]) == [1, 2, 3]
            @test f([1, 2, 1]) == [1, 3, 2]
            @test f([1, 2, 2]) == [1, 2, 3]
            @test f([1, 1, 1]) == [1, 2, 3]
            @test f([2, 1, 2]) == [1, 3, 2]
            @test f([1, 2, 1, 3, 3, 2]) == [1, 3, 2, 6, 4, 5]
        end

        @testset "reshape_data_to_groups" begin
            # Arrange
            f = (data, group_ids) -> Data.reshape_data_to_groups(data, group_ids)

            # Assert
            @test size(f(rand(2, 4, 6), [1, 2, 3])) == (2, 4, 6)
            @test size(f(rand(2, 4, 6), [1, 2, 1])) == (12, 4)
            @test size(f(rand(2, 4, 6), [1, 2, 2])) == (2, 24)
            @test size(f(rand(2, 4, 6), [1, 1, 1])) == (48,)
            @test size(f(rand(2, 4, 6), [1, 1, 2])) == (8, 6)
            @test size(f(rand(2, 3, 4, 5, 6, 7), [1, 2, 1, 3, 3, 2])) == (8, 21, 30)
        end

        @testset "filter_dim_selection" begin
            # Arrange
            f = (dim_selection, dims) -> Data.filter_dim_selection(
                Dict{String, Int}(dim_selection), dims)

            # Assert
            @test f(Dict("a" => 1, "b" => 2, "c" => 3), ["a"]) == Dict("b" => 2, "c" => 3)
            @test f(Dict("a" => 1, "b" => 2, "c" => 3), ["b", "c"]) == Dict("a" => 1)
            @test f(Dict("a" => 1, "b" => 2, "c" => 3), ["d"]) == Dict("a" => 1, "b" => 2, "c" => 3)
            @test f(Dict("a" => 1, "b" => 2, "c" => 3), ["a", "b", "c"]) == Dict()
        end
    end

    @testset "Data Extraction" begin
        @testset "Regular Data - No Interpolation" begin
            # Arrange
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

        @testset "Regular Data - Interpolation" begin
            # Arrange
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
            dataset.interp.rc.lon = 1:10
            dataset.interp.rc.only_long = 1:11
            dataset.interp.rc.untaken = 1:12

            # Act: (get the data shape)
            gdata_shape = (var, plot_dims) -> Data.get_data(dataset, var, plot_dims, dimension_selections).size

            # Assert
            @test gdata_shape("1d_float", ["lon"]) == (10,)
            @test gdata_shape("2d_float", ["lon"]) == (10,)
            @test gdata_shape("2d_float", ["lon", "lat"]) == (10, 7)
            @test gdata_shape("2d_float", ["lat", "lon"]) == (7, 10)
            @test gdata_shape("2d_gap", ["lon"]) == (10,)
            @test gdata_shape("2d_gap_inv", ["lon"]) == (10,)
            @test gdata_shape("2d_gap", ["lon", "float_dim"]) == (10, 6)
            @test gdata_shape("2d_gap_inv", ["lon", "float_dim"]) == (10, 6)
            @test gdata_shape("5d_float", ["lon", "lat", "only_long"]) == (10, 7, 11)
            @test gdata_shape("int_var", ["lat"]) == (7,)
            @test gdata_shape("string_var", ["string_dim"]) == (3,)
            @test gdata_shape("untaken_dim", ["untaken"]) == (12, )
        end

        @testset "Unstructured Data" begin
            dataset = make_unstructured_temp_dataset()
            rc = dataset.interp.rc
            dimension_selections = Dict(
                "time" => 2,
                "clon" => 120,
                "clat" => 240,
                "vlon" => 130,
                "vlat" => 250,
                "depth" => 4,
            )

            # Act: (get the data shape)
            gdata_shape = (var, plot_dims) -> Data.get_data(dataset, var,
                plot_dims, dimension_selections).size

            # Assert
            @test gdata_shape("zos", ["time"]) == (5, )
            @test gdata_shape("zos", ["clon"]) == (length(rc.clat),)
            @test gdata_shape("zos", ["clat"]) == (length(rc.clon),)
            @test gdata_shape("zos", ["clon", "clat"]) == (length(rc.clon), length(rc.clat))
            @test gdata_shape("zos", ["time", "clon"]) == (5, length(rc.clat))
            @test gdata_shape("u", ["clon", "depth"]) == (length(rc.clat), 10)
            @test gdata_shape("v", ["clat", "time"]) == (length(rc.clon), 5)
        end

        @testset "Semi Unstructured Data" begin
            dataset = make_semi_unstructured_temp_dataset()
            rc = dataset.interp.rc
            dimension_selections = Dict(
                "time" => 2,
                "lon" => 120,
                "lat" => 240,
            )

            # Act: (get the data shape)
            gdata_shape = (var, plot_dims) -> Data.get_data(dataset, var,
                plot_dims, dimension_selections).size

            # Assert
            @test gdata_shape("temp", ["time"]) == (5, )
            @test gdata_shape("temp", ["lon"]) == (length(rc.lat),)
            @test gdata_shape("temp", ["lat"]) == (length(rc.lon),)
            @test gdata_shape("temp", ["lon", "lat"]) == (length(rc.lon), length(rc.lat))
            @test gdata_shape("temp", ["time", "lon"]) == (5, length(rc.lat))
            @test gdata_shape("mask", ["lon"]) == (length(rc.lat),)
            @test gdata_shape("mask", ["lat"]) == (length(rc.lon),)
        end

    end

end
