using Test
using Dates
using ArgParse
using Suppressor
using ZarrDatasets
using CDFViewer
using CDFViewer.Constants
using CDFViewer.Data

# ========================================
#  Zarr store helpers
# ========================================

# Deterministic payload so values can be asserted after reading back
zarr_temp_data() = reshape(collect(Float64, 1:5*7*4), (5, 7, 4))

"""
Build a small xarray-style zarr v2 store in a tempdir (no consolidated
`.zmetadata`, `_ARRAY_DIMENSIONS` attributes on every array — the same layout
the Python fixture writer produces). Includes a CF time axis, units/long_name
attributes and a staggered-dims pair (`u` on `x` vs `u_right` on `x_right`).
"""
function init_temp_zarr_store()::String
    dir = joinpath(mktempdir(), "test_store.zarr")
    ZarrDataset(dir, "c") do ds
        # Coordinates
        defVar(ds, "lon", collect(1.0:5.0), ("lon",), attrib = Dict(
            "units" => "degrees_east", "long_name" => "Longitude"))
        defVar(ds, "lat", collect(10.0:2.0:22.0), ("lat",), attrib = Dict(
            "units" => "degrees_north", "long_name" => "Latitude"))
        defVar(ds, "time", [0.0, 3600.0, 7200.0, 10800.0], ("time",),
            attrib = Dict("units" => "seconds since 2000-01-01 00:00:00"))
        # Staggered grid coordinates
        defVar(ds, "x", collect(0.0:5.0), ("x",), attrib = Dict("units" => "m"))
        defVar(ds, "x_right", collect(0.5:5.5), ("x_right",), attrib = Dict("units" => "m"))
        # Variables
        defVar(ds, "temp", zarr_temp_data(), ("lon", "lat", "time"), attrib = Dict(
            "units" => "m/s", "long_name" => "temperature"))
        defVar(ds, "u", collect(1.0:6.0), ("x",), attrib = Dict("units" => "m/s"))
        defVar(ds, "u_right", collect(2.0:7.0), ("x_right",), attrib = Dict("units" => "m/s"))
    end
    dir
end

"""
Assertions that must hold for any zarr store opened through `Data.CDFDataset`.
Fixture-based integration tests (test/data/zarr/) can reuse this on their
opened stores.
"""
function check_zarr_store_basics(dataset::Data.CDFDataset)
    @test dataset isa Data.CDFDataset
    @test !isempty(dataset.dimensions)
    @test !isempty(dataset.variables)
    for var in dataset.variables
        # every variable dimension resolves to a known coordinate
        @test all(d -> d in dataset.coordinates, Data.get_var_dims(dataset, var))
        @test Data.get_label(dataset, var) isa String
        @test haskey(dataset.group_ids_of_var_dims, var)
    end
    for coord in dataset.coordinates
        @test length(Data.get_dim_values(dataset, coord)) > 0
    end
end

# ========================================
#  Tests
# ========================================

@testset "Zarr support" begin

    @testset "Detection" begin
        store = init_temp_zarr_store()
        nc_file = init_temp_dataset()

        @test Data.is_zarr_store(store)
        @test Data.is_zarr_store(store * "/")
        # .zarr suffix is enough, even if the path does not exist (yet)
        @test Data.is_zarr_store(tempname() * ".zarr")
        # a bare directory is treated as a zarr store
        @test Data.is_zarr_store(mktempdir())
        # NetCDF files are not zarr stores
        @test !Data.is_zarr_store(nc_file)
        @test !Data.is_zarr_store(tempname() * ".nc")
    end

    @testset "Open store" begin
        store = init_temp_zarr_store()
        dataset = Data.CDFDataset([store])
        check_zarr_store_basics(dataset)

        # Dimensions / coordinates / variables
        @test issetequal(dataset.dimensions, ["lon", "lat", "time", "x", "x_right"])
        @test issetequal(dataset.coordinates, ["lon", "lat", "time", "x", "x_right"])
        @test issetequal(dataset.variables, ["temp", "u", "u_right"])
        @test dataset.var_coords["temp"] == ["lon", "lat", "time"]

        # Staggered dims: u lives on x, u_right on x_right
        @test dataset.var_coords["u"] == ["x"]
        @test dataset.var_coords["u_right"] == ["x_right"]
        g = dataset.interp.group_map
        @test g["x"] != g["x_right"]

        # Coordinate values
        @test Data.get_dim_values(dataset, "lon") == collect(1.0:5.0)
        @test Data.get_dim_values(dataset, "x_right") == collect(0.5:5.5)

        # CF time axis is decoded to DateTime like NetCDF
        @test eltype(dataset.ds["time"]) <: Union{Missing, Dates.DateTime}
        @test dataset.ds["time"][2] == Dates.DateTime(2000, 1, 1, 1)
        @test Data.get_dim_value_label(dataset, "time", 2) ==
            "  → time: 2000-01-01 01:00:00"

        # Labels from long_name / units attributes
        @test Data.get_label(dataset, "temp") == "temperature [m/s]"
        @test Data.get_label(dataset, "lon") == "Longitude [degrees_east]"

        # Data values round-trip
        sel = Dict("time" => 2, "lon" => 1, "lat" => 1, "x" => 1, "x_right" => 1)
        @test Data.get_data(dataset, "temp", ["lon", "lat"], sel) ==
            zarr_temp_data()[:, :, 2]
        @test Data.get_data(dataset, "u", ["x"], sel) == collect(1.0:6.0)
        @test Data.get_data(dataset, "u_right", ["x_right"], sel) == collect(2.0:7.0)

        # Overview shows the store name and its content
        ov = Data.overview_string(dataset; color = false)
        @test occursin("test_store.zarr", ov)
        @test occursin("temperature", ov)
        @test occursin("2000-01-01", ov)
    end

    @testset "Error paths" begin
        store = init_temp_zarr_store()

        # Multiple zarr stores (or zarr mixed with NetCDF) are not supported
        err = @test_throws ErrorException Data.CDFDataset([store, store])
        @test occursin("NetCDF-only", sprint(showerror, err.value))
        nc_file = init_temp_dataset()
        err = @test_throws ErrorException Data.CDFDataset([nc_file, store])
        @test occursin("NetCDF-only", sprint(showerror, err.value))

        # Nonexistent paths give a clear error
        missing_path = tempname() * ".zarr"
        err = @test_throws ErrorException Data.CDFDataset([missing_path])
        @test occursin("not found", sprint(showerror, err.value))
        @test occursin(missing_path, sprint(showerror, err.value))
    end

    @testset "savefig on a zarr store" begin
        store = init_temp_zarr_store()
        out_dir = mktempdir()
        args = parse_args(
            [store, "-v", "temp", "-x", "lon", "-y", "lat", "-p", "heatmap",
             "--savefig", "-s", "filename=\"temp_map.png\""],
            CDFViewer.get_arg_parser())
        cd(out_dir) do
            @suppress @test julia_main(parsed_args = args) == 0
        end
        @test isfile(joinpath(out_dir, "temp_map.png"))
        @test filesize(joinpath(out_dir, "temp_map.png")) > 0
    end

end
