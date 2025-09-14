using Test
using CDFViewer.Interpolate
using NearestNeighbors

@testset "Interpolate.jl" begin

    @testset "Constructor" begin
        @testset "Regular Data" begin
            # Arange
            dataset = make_temp_dataset()

            # Act
            interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)

            # Assert: Regular data should have no ranges
            for r in values(interp.ranges)
                @test r === nothing
            end

            # Assert: All trees should be initialized
            for tree in values(interp.trees)
                @test tree isa KDTree
            end
        end

        @testset "Unstructured Data" begin
            # Arange
            dataset = make_unstructured_temp_dataset()

            # Act
            interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)

            # Assert: Non-paired coordinates should have no ranges
            for coord in ["time", "depth"]
                @test interp.ranges[coord] === nothing
            end

            # Assert: Paired coordinates should have ranges
            for coord in ["clon", "clat", "vlon", "vlat"]
                @test interp.ranges[coord] !== nothing
                @test minimum(interp.ranges[coord]) ≈ minimum(dataset.ds[coord][:])
                @test maximum(interp.ranges[coord]) ≈ maximum(dataset.ds[coord][:])
            end

            # Assert: All trees should be initialized
            for tree in values(interp.trees)
                @test tree isa KDTree
            end
            # Assert: Paired coordinates should be in the same group
            @test interp.group_map["clon"] == interp.group_map["clat"]
            @test interp.group_map["vlon"] == interp.group_map["vlat"]
        end
    end

    @testset "Control Properties" begin
        @testset "set range" begin
            function test_set_range(dataset, coord, new_range, expected_range, expect_cache)
                # Arange
                interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)
                group_id = interp.group_map[coord]
                # Set an initial cache value to check if it gets removed
                interp.index_cache[group_id] = [1]

                # Act
                Interpolate.set_range!(interp, coord, new_range)

                # Assert
                @test interp.ranges[coord] === expected_range
                @test haskey(interp.index_cache, group_id) == expect_cache

                # Act: Set again to the same value and check that index_cache is not modified
                interp.index_cache[group_id] = [1]
                Interpolate.set_range!(interp, coord, new_range)

                # Assert
                @test interp.ranges[coord] === expected_range
                @test haskey(interp.index_cache, group_id)
            end

            @testset "Regular Data" begin
                # Arange
                dataset = make_temp_dataset()

                for ranges in [nothing, 1:10, LinRange(0.0, 1.0, 5), [0.1, 0.5, 0.9]]
                    @testset "Set $ranges" begin
                        test_set_range(dataset, "lon", ranges, ranges, isnothing(ranges))
                    end
                end
            end

            @testset "Unstructured Data" begin
                # Arange
                dataset = make_unstructured_temp_dataset()

                # Test setting ranges for paired coordinates
                for coord in ["clon", "vlat"]

                    for ranges in [nothing, 1:10]
                        @testset "Set $ranges for $coord" begin
                            test_set_range(dataset, coord, ranges,
                                isnothing(ranges) ? Interpolate.compute_range(dataset.ds, coord) : ranges,
                                isnothing(ranges))
                        end
                    end
                end

                # Test setting ranges for non-paired coordinates
                for coord in ["time", "depth"]
                    for ranges in [nothing, 1:10]
                        @testset "Set $ranges for $coord" begin
                            test_set_range(dataset, coord, ranges, ranges, isnothing(ranges))
                        end
                    end
                end
            end

        end

    end

    @testset "Range Controller" begin
        @testset "propertynames" begin
            # Arange
            dataset = make_temp_dataset()
            interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)

            # Act
            props = propertynames(interp.rc)

            # Assert
            for valid_key in [:lat, :lon, :time]
                @test valid_key in props
            end
            for invalid_key in [:ranges, :group_map, :groups, :index_cache, :trees]
                @test invalid_key ∉ props
            end
        end

        @testset "getproperty" begin
            # Arange
            dataset = make_temp_dataset()
            interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)

            # Assert: Accessing interp.rc.interp
            @test interp.rc.interp === interp

            # Assert: Accessing coordinates with no given range
            @test interp.rc.lat ≈ dataset.ds["lat"][:]
            @test interp.rc.lon ≈ dataset.ds["lon"][:]

            # Act: Set ranges
            new_range = 1:0.5:10
            Interpolate.set_range!(interp, "lat", new_range)

            # Assert: Accessing coordinates with given range
            @test interp.rc.lat === new_range

            # Act: Set back to nothing
            Interpolate.set_range!(interp, "lat", nothing)

            # Assert: Accessing coordinates with no given range
            @test interp.rc.lat ≈ dataset.ds["lat"][:]
        end

        @testset "setproperty!" begin
            # Arange
            dataset = make_temp_dataset()
            interp = Interpolate.Interpolator(dataset.ds, dataset.paired_coords)
            interp.index_cache[interp.group_map["lon"]] = [1]

            # Act
            interp.rc.lon = 1:5
            @test interp.ranges["lon"] === 1:5
            @test !haskey(interp.index_cache, interp.group_map["lon"])
        end
    end

    @testset "Interpolate Variable" begin
        @testset "Regular Data - No Interpolation" begin
            # Arange
            dataset = make_temp_dataset()
            ds = dataset.ds
            interp = Interpolate.Interpolator(ds, dataset.paired_coords)
            data = ds["4d_float"][:,:,:,:]

            # Act
            new_data = Interpolate.interpolate(interp, data,
                [["lon"], ["lat"], ["time"], ["float_dim"]],
                ["time", "lat", "float_dim", "lon"],
                Dict{String, Int}()
                )

            # Assert
            @test size(new_data) == (length(ds["time"]), length(ds["lat"]), length(ds["float_dim"]), length(ds["lon"]))
            @test eltype(new_data) == eltype(ds["4d_float"][:])
        end

        @testset "Regular Data - Interpolation" begin
            @testset "1D Interpolation in 1D Array" begin
                dataset = make_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                data = ds["1d_float"][:]
                interp.rc.lon = 1:0.1:10

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["lon"]], ["lon"], Dict{String, Int}())

                # Assert
                @test length(new_data) == length(interp.rc.lon)
            end

            @testset "Point in 1D Array" begin
                dataset = make_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                data = ds["1d_float"][:]
                interp.rc.lon = 1:0.1:10

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["lon"]], String[], Dict("lon" => 5))

                # Assert
                @test size(new_data) == ()
                @test length(new_data) == 1
            end

            @testset "1D Interpolation in 3D Array" begin
                for coord in ["lat", "time", "float_dim"]
                    @testset "Coordinate: $coord" begin
                        dataset = make_temp_dataset()
                        ds = dataset.ds
                        interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                        data = ds["3d_float"][:,:,:]
                        setproperty!(interp.rc, Symbol(coord), 1:0.1:10)

                        # Act
                        new_data = Interpolate.interpolate(interp, data,
                            [["lon"], ["lat"], ["time"]],
                            ["lat", "time", "lon"],
                            Dict{String, Int}())

                        # Assert
                        @test size(new_data) == (length(interp.rc.lat), length(interp.rc.time), length(interp.rc.lon))
                    end
                end
            end

            @testset "Point Interpolation of a 3D Array" begin
                dataset = make_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                data = ds["3d_float"][:,:,:]
                interp.rc.time = 1:0.1:10

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["lon"], ["lat"], ["time"]],
                    ["lat", "lon"],
                    Dict("time" => 43))

                # Assert
                @test size(new_data) == (length(interp.rc.lat), length(interp.rc.lon))
            end

            @testset "Complex Interpolation of a 5D array" begin
                dataset = make_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                rc = interp.rc
                data = ds["5d_float"][:,:,:,:,:]
                rc.lat = 1:0.1:10
                rc.float_dim = 1:0.2:5
                rc.only_unit = 1:0.5:3

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["lon"], ["lat"], ["float_dim"], ["only_unit"], ["only_long"]],
                    ["only_long", "float_dim", "lon"],
                    Dict("only_unit" => 2, "lat" => 3))

                # Assert
                @test size(new_data) == (length(rc.only_long), length(rc.float_dim), length(rc.lon))
            end
        end

        @testset "Unstructured - Interpolation" begin
            @testset "2D Interpolation in 1D Array" begin
                dataset = make_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                dataset.var_coords
                data = ds["zos"][1,:]

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["clon", "clat"]], ["clon", "clat"], Dict{String, Int}())

                # Assert
                @test size(new_data) == (length(interp.rc.clon), length(interp.rc.clat))

                # Uncomment to visualize the result
                # using GLMakie
                # heatmap(interp.rc.clon, interp.rc.clat, new_data)
                # scatter!(ds["clon"][:], ds["clat"][:], color=:white, markersize=14)
                # scatter!(ds["clon"][:], ds["clat"][:], color=ds["zos"][1,:], markersize=8)
            end

            @testset "2D interpolation in 1D Array with Selected Dim" begin
                dataset = make_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                dataset.var_coords
                data = ds["zos"][1,:]

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["clon", "clat"]], ["clon"], Dict("clat" => 200))

                # Assert
                @test length(new_data) == length(interp.rc.clon)

                # Uncomment to visualize the result
                # using GLMakie
                # scatter(interp.rc.clon, fill(interp.rc.clat[200], length(interp.rc.clon)), color=new_data)
                # scatter!(ds["clon"][:], ds["clat"][:], color=:black, markersize=14)
                # scatter!(ds["clon"][:], ds["clat"][:], color=ds["zos"][1,:], markersize=8)
            end

            @testset "2D interpolation in 2D Array" begin
                dataset = make_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                dataset.var_coords
                data = ds["zos"][:,:]

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["time"], ["clon", "clat"]], ["time", "clon", "clat"], Dict{String, Int}())

                # Assert
                @test size(new_data) == (length(interp.rc.time), length(interp.rc.clon), length(interp.rc.clat))

                # Uncomment to visualize the result
                # using GLMakie
                # heatmap(interp.rc.clon, interp.rc.clat, new_data[3,:,:])
                # scatter!(ds["clon"][:], ds["clat"][:], color=:black, markersize=14)
                # scatter!(ds["clon"][:], ds["clat"][:], color=ds["zos"][3,:], markersize=8)
            end

            @testset "Complex Interpolation" begin
                dataset = make_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                dataset.var_coords
                data = ds["u"][:,:,:]

                # Act: Default Interpolation
                new_data = Interpolate.interpolate(interp, data,
                    [["time"], ["depth"], ["clon", "clat"]], ["time", "depth", "clat"], Dict("clon" => 100))

                # Assert
                @test size(new_data) == (length(interp.rc.time), length(interp.rc.depth), length(interp.rc.clat))

                # Act: Change the depth range
                interp.rc.depth = LinRange(0, 5000, 4)
                old_cache = interp.index_cache[interp.group_map["clon"]]
                new_data = Interpolate.interpolate(interp, data, 
                    [["time"], ["depth"], ["clon", "clat"]], ["time", "clat"], Dict("clon" => 100, "depth" => 2))

                # Assert
                @test size(new_data) == (length(interp.rc.time), length(interp.rc.clat))
                @test interp.index_cache[interp.group_map["clon"]] == old_cache  # Cache should not be recomputed

                # Act: Change the lon range
                interp.rc.clon = LinRange(0, 1, 50)
                new_data = Interpolate.interpolate(interp, data,
                    [["time"], ["depth"], ["clon", "clat"]], ["time", "clon", "clat"], Dict("depth" => 1))

                # Assert
                @test size(new_data) == (length(interp.rc.time), length(interp.rc.clon), length(interp.rc.clat))
                @test interp.index_cache[interp.group_map["clon"]] != old_cache  # Cache should be recomputed

                # Uncomment to visualize the result
                # using GLMakie
                # heatmap(interp.rc.clon, interp.rc.clat, new_data[1,:,:])
                # scatter!(ds["clon"][:], ds["clat"][:], color=:black, markersize=14)
                # scatter!(ds["clon"][:], ds["clat"][:], color=ds["u"][1,1,:], markersize=8)
            end

        end

        @testset "Semi-Unstructured - Interpolation" begin
            @testset "Lon - Lat Array" begin
                dataset = make_semi_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                dataset.var_coords
                data = ds["mask"][:]

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["lon", "lat"]], ["lon", "lat"], Dict{String, Int}())

                # Assert
                @test size(new_data) == (length(interp.rc.lon), length(interp.rc.lat))

                # Uncomment to visualize the result
                # using GLMakie
                # heatmap(interp.rc.lon, interp.rc.lat, new_data)
                # scatter!(ds["lon"][:], ds["lat"][:], color=:black, markersize=14)
                # scatter!(ds["lon"][:], ds["lat"][:], color=ds["mask"][:], markersize=8)
            end

            @testset "Time - Lon - Lat Array" begin
                dataset = make_semi_unstructured_temp_dataset()
                ds = dataset.ds
                interp = Interpolate.Interpolator(ds, dataset.paired_coords)
                rc = interp.rc
                dataset.var_coords
                data = ds["temp"][:,:,:]
                ntime = ds.dim["time"]
                nx = ds.dim["x"]
                ny = ds.dim["y"]
                data = reshape(data, (ntime, nx*ny))

                # Act
                new_data = Interpolate.interpolate(interp, data,
                    [["time"], ["lon", "lat"]], ["time", "lon", "lat"], Dict{String, Int}())

                # Assert
                @test size(new_data) == (length(rc.time), length(rc.lon), length(rc.lat))

                # Uncomment to visualize the result
                # using GLMakie
                # ind = 2
                # heatmap(rc.lon, rc.lat, new_data[ind,:,:])
                # scatter!(ds["lon"][:], ds["lat"][:], color=:black, markersize=14)
                # scatter!(ds["lon"][:], ds["lat"][:], color=data[ind,:], markersize=8)

                # Act: Slice
                new_data = Interpolate.interpolate(interp, data,
                    [["time"], ["lon", "lat"]], ["time", "lon"], Dict("lat" => 100))

                # using GLMakie
                # ind = 4
                # scatter(rc.lon, fill(rc.lat[100], length(rc.lon)), color=new_data[ind,:])
                # scatter!(ds["lon"][:], ds["lat"][:], color=:black, markersize=14)
                # scatter!(ds["lon"][:], ds["lat"][:], color=data[ind,:], markersize=8)
            end
        end

    end

    @testset "Interpolate Dimension" begin
        @testset "Point from 1D array" begin
            # Arrange
            dataset = make_temp_dataset()
            ds = dataset.ds
            interp = Interpolate.Interpolator(ds, dataset.paired_coords)
            data = ds["1d_float"][:]
            interp.rc.lon = 1:0.1:10

            # Act
            new_data, new_coords = Interpolate.interpolate_dimension(
                interp, data, 1, ["lon"], Dict("lon" => 5))

            # Assert
            @test isempty(new_coords)
            @test size(new_data) == ()

        end

    end

    @testset "Unit Tests" begin
        @testset "compute_nn_indices" begin
            @testset "1D Data" begin
                # Arange
                x = LinRange(0.001, 0.999, 100)
                tree = KDTree(x')
                new_x = LinRange(0, 1, 10)

                # Act
                nn_indices = Interpolate.compute_nn_indices(tree, [new_x])

                # Assert
                @test length(nn_indices) == length(new_x)
                @test isapprox(x[nn_indices], collect(new_x); atol = 0.01)
            end

            @testset "2D Data" begin
                # Arange
                N = 1_000
                x = rand(N)
                y = rand(N)
                tree = KDTree(hcat(x, y)')
                new_x = LinRange(0, 1, 10)
                new_y = LinRange(0, 1, 14)

                # Act
                nn_indices = Interpolate.compute_nn_indices(tree, [new_x, new_y])

                # Assert
                @test size(nn_indices) == (length(new_x), length(new_y))
                # for j in 1:length(new_y)
                #     @test isapprox(x[nn_indices][:,j], collect(new_x); atol = 0.1)
                # end
                # for i in 1:length(new_x)
                #     @test isapprox(y[nn_indices][i,:], collect(new_y); atol = 0.1)
                # end
            end

            @testset "3D Data" begin
                # Arange
                N = 1_000
                x = rand(N)
                y = rand(N)
                z = rand(N)
                tree = KDTree(hcat(x, y, z)')
                new_x = LinRange(0, 1, 10)
                new_y = LinRange(0, 1, 14)
                new_z = LinRange(0, 1, 8)

                # Act
                nn_indices = Interpolate.compute_nn_indices(tree, [new_x, new_y, new_z])

                # Assert
                @test size(nn_indices) == (length(new_x), length(new_y), length(new_z))
                # for j in 1:length(new_y), k in 1:length(new_z)
                #     @test isapprox(x[nn_indices][:,j,k], collect(new_x); atol = 0.3)
                # end
                # for i in 1:length(new_x), k in 1:length(new_z)
                #     @test isapprox(y[nn_indices][i,:,k], collect(new_y); atol = 0.3)
                # end
                # for i in 1:length(new_x), j in 1:length(new_y)
                #     @test isapprox(z[nn_indices][i,j,:], collect(new_z); atol = 0.3)
                # end
            end
        end

        @testset "get_indexing_tuple" begin
            @test Interpolate.get_indexing_tuple(["lat"], Dict{String, Int}()) == (Colon(),)
            @test Interpolate.get_indexing_tuple(["lon"], Dict("lon" => 10)) == (10,)
            @test Interpolate.get_indexing_tuple(["lat", "lon"], Dict("lon" => 10)) == (Colon(), 10)
            @test Interpolate.get_indexing_tuple(["lat", "lon"], Dict("lat" => 5)) == (5, Colon())
            @test Interpolate.get_indexing_tuple(["lat", "lon"], Dict("lat" => 5, "lon" => 10)) == (5, 10)
            @test Interpolate.get_indexing_tuple(["lat", "lon", "depth"], Dict("lon" => 10, "depth" => 5)) == (Colon(), 10, 5)
            @test Interpolate.get_indexing_tuple(["lat", "lon", "depth"], Dict("lat" => 3, "depth" => 5)) == (3, Colon(), 5)
        end 

        @testset "filter_nn_selection" begin
            # Arange
            nn_indices = Array{Int}(undef, 9, 4, 5, 3)  # 3D array
            dim_selection = Dict("lon" => 3, "depth" => 2)
            group = ["lat", "lon", "time", "depth"]

            # Act
            result = Interpolate.filter_nn_selection(nn_indices, dim_selection, group)

            # Assert
            @test result isa SubArray{Int}
            @test size(result) == (9, 5)
        end

        @testset "compute_new_shape" begin
            @test Interpolate.compute_new_shape((10,), (4, 3), 1) == (4, 3)
            @test Interpolate.compute_new_shape((10, 5), (4, 3), 1) == (4, 3, 5)
            @test Interpolate.compute_new_shape((10, 5), (4, 3), 2) == (10, 4, 3)
            @test Interpolate.compute_new_shape((10, 5, 6), (4, ), 1) == (4, 5, 6)
            @test Interpolate.compute_new_shape((10, 5, 6), (), 2) == (10, 6)
        end

        @testset "compute_filtered_group_coords" begin
            f = Interpolate.compute_filtered_group_coords
            @test f(["lat", "lon", "time", "depth"], Dict("lon" => 10, "depth" => 5)) == ["lat", "time"]
            @test f(["lat", "lon", "time", "depth"], Dict("lat" => 3, "depth" => 5)) == ["lon", "time"]
            @test f(["lat"], Dict{String, Int}()) == ["lat"]
            @test f(["lon"], Dict("lon" => 10)) == String[]
        end

        @testset "apply_on_axis!" begin
            @testset "Point from 1D array" begin
                # Arange
                input_data = collect(1:10)
                output_data = similar(input_data, ())
                in_axis = 1
                out_axes = Int[]

                function my_func(x)
                    99
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                # output data should be a 0-dimensional array
                @test ndims(output_data) == 0
                # output data should contain the value 99
                @test output_data[] == 99
            end

            @testset "Point from 2D array (second coord)" begin
                # Arange
                input_data = rand(10, 6)
                output_data = similar(input_data, (10,))
                in_axis = 2
                out_axes = Int[]

                function my_func(x)
                    x[1]
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                @test size(output_data) == (10,)
                # output data should contain the first column of input data
                @test output_data == input_data[:, 1]
            end

            @testset "Point from 2D array (first coord)" begin
                # Arange
                input_data = rand(6, 10)
                output_data = similar(input_data, (10,))
                in_axis = 1
                out_axes = Int[]

                function my_func(x)
                    x[1]
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                @test size(output_data) == (10,)
                # output data should contain the first row of input data
                @test output_data == input_data[1, :]
            end

            @testset "1D reshape" begin
                # Arange
                input_data = rand(10)
                output_data = similar(input_data, (5, 2))
                in_axis = 1
                out_axes = [1, 2]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                @test output_data == reshape(input_data, 5, 2)
            end

            @testset "2D reshape (first coord)" begin
                # Arange
                input_data = rand(10, 6)
                output_data = similar(input_data, (5, 2, 6))
                in_axis = 1
                out_axes = [1, 2]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                for j in 1:6
                    @test output_data[:, :, j] == reshape(input_data[:, j], 5, 2)
                end
            end

            @testset "2D reshape (second coord)" begin
                # Arange
                input_data = rand(6, 10)
                output_data = similar(input_data, (6, 5, 2))
                in_axis = 2
                out_axes = [2, 3]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                for i in 1:6
                    @test output_data[i, :, :] == reshape(input_data[i, :], 5, 2)
                end
            end

            @testset "3D reshape (first coord)" begin
                # Arange
                input_data = rand(10, 6, 4)
                output_data = similar(input_data, (5, 2, 6, 4))
                in_axis = 1
                out_axes = [1, 2]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                for i in 1:6, k in 1:4
                    @test output_data[:, :, i, k] == reshape(input_data[:, i, k], 5, 2)
                end
            end

            @testset "3D reshape (second coord)" begin
                # Arange
                input_data = rand(6, 10, 4)
                output_data = similar(input_data, (6, 5, 2, 4))
                in_axis = 2
                out_axes = [2, 3]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                for i in 1:6, k in 1:4
                    @test output_data[i, :, :, k] == reshape(input_data[i, :, k], 5, 2)
                end
            end

            @testset "3D reshape (third coord)" begin
                # Arange
                input_data = rand(6, 4, 10)
                output_data = similar(input_data, (6, 4, 5, 2))
                in_axis = 3
                out_axes = [3, 4]

                function my_func(x)
                    reshape(x, 5, 2)
                end

                # Act
                Interpolate.apply_on_axis!(input_data, output_data, in_axis, out_axes, x -> my_func(x))

                # Assert
                for i in 1:6, j in 1:4
                    @test output_data[i, j, :, :] == reshape(input_data[i, j, :], 5, 2)
                end
            end

        end

        @testset "reorder_dimensions" begin
            @testset "Multidimensional array" begin
                # Arrange
                input_data = reshape(collect(1:24), 4, 3, 2)  # 3D array
                new_dims = ["lon", "lat", "depth"]
                out_dims = ["lat", "depth", "lon"]

                # Act
                new_data = Interpolate.reorder_dimensions(input_data, new_dims, out_dims)

                # Assert
                @test size(new_data) == (3, 2, 4)
                @test new_data[:, :, :] == permutedims(input_data, (2, 3, 1))
            end

            @testset "0-dimensional array" begin
                # Arrange
                input_data = fill(42, ())  # 0D array
                new_dims = String[]
                out_dims = String[]

                # Act
                new_data = Interpolate.reorder_dimensions(input_data, new_dims, out_dims)

                # Assert
                @test size(new_data) == ()
                @test new_data[] == 42
            end
        end

        @testset "get_this_dim_selection" begin
            dim_selection = Dict(
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

            @test Interpolate.get_this_dim_selection(dim_selection, ["lon"]) == Dict("lon" => 2)
            @test Interpolate.get_this_dim_selection(dim_selection, ["lat", "lon"]) == Dict("lat" => 3, "lon" => 2)
            @test Interpolate.get_this_dim_selection(dim_selection, ["float_dim", "only_unit"]) == Dict("float_dim" => 4, "only_unit" => 1)
            @test Interpolate.get_this_dim_selection(dim_selection, ["untaken"]) == Dict("untaken" => 2)
            @test Interpolate.get_this_dim_selection(dim_selection, ["not_in_dict"]) == Dict{String, Int}()
        end
    end

end
