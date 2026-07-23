using Test
using Dates
using ArgParse
using Suppressor
using CDFViewer
using CDFViewer.Data
using CDFViewer.Interpolate

# ========================================
#  Integration tests against the Python-generated zarr fixtures
#
#  The stores in test/data/zarr/ are written by the real fridom framework2
#  tensorstore-backed zarr writer: zarr v2, xarray-style `_ARRAY_DIMENSIONS`,
#  no consolidated `.zmetadata`, blosc/lz4 compression, and an auxiliary
#  `iteration(time)` coordinate referenced by every data variable through the
#  `coordinates` attribute.
#
#  Python writes time-first, C-order (e.g. temp[time, x, y]); Julia sees the
#  reversed dimension order (temp[y, x, time]) with 1-based indices.
# ========================================

const ZARR_FIXTURE_DIR = joinpath(@__DIR__, "data", "zarr")

open_fixture(name::String) = Data.CDFDataset([joinpath(ZARR_FIXTURE_DIR, name)])

# Every fixture carries a 1-D `iteration(time)` auxiliary coordinate that the
# data variables reference through the `coordinates` attribute. Because it
# shares its whole axis with the `time` dimension coordinate, it must not
# replace it: `time` stays the variables' coordinate and `iteration` is left
# as a plain (still readable) variable.
function check_time_coordinate(dataset::Data.CDFDataset, nsteps::Int)
    @test "time" in dataset.coordinates
    @test "iteration" ∉ dataset.coordinates
    @test "iteration" in dataset.variables
    @test length(Data.get_dim_values(dataset, "time")) == nsteps
end

@testset "Zarr fixtures (Python writer)" begin

    @testset "2d_scalar" begin
        dataset = open_fixture("2d_scalar.zarr")
        check_zarr_store_basics(dataset)
        @test issetequal(dataset.dimensions, ["time", "x", "y"])
        @test issetequal(dataset.variables, ["temp", "iteration"])
        @test issetequal(dataset.coordinates, ["x", "y", "time"])
        check_time_coordinate(dataset, 5)
        # plain "seconds" time axis (no reference date) stays numeric
        @test eltype(dataset.ds["time"]) <: Float64
        @test Interpolate.convert_to_float64(dataset.ds, "time") ==
            [0.0, 0.5, 1.0, 1.5, 2.0]
        # ground truth: Python temp[0,0,0]; Julia dims are (y, x, time)
        @test dataset.ds["temp"][1, 1, 1] == 0.19134171618254486
        @test Data.get_label(dataset, "temp") == "Temperature [k]"  # units are lowercased
        @test size(Data.get_data(dataset, "temp", ["x", "y"], Dict("time" => 1))) ==
            (16, 16)
        close(dataset.ds)
    end

    @testset "3d_vector (staggered C-grid)" begin
        dataset = open_fixture("3d_vector.zarr")
        check_zarr_store_basics(dataset)
        @test issetequal(dataset.variables, ["u", "v", "w", "p", "iteration"])
        @test issetequal(dataset.coordinates,
            ["x", "x_right", "y", "y_right", "z", "z_outer", "time"])
        check_time_coordinate(dataset, 3)
        # each velocity component lives on its own staggered axis
        @test issetequal(dataset.var_coords["u"], ["x_right", "y", "z", "time"])
        @test issetequal(dataset.var_coords["v"], ["x", "y_right", "z", "time"])
        @test issetequal(dataset.var_coords["w"], ["x", "y", "z_outer", "time"])
        @test issetequal(dataset.var_coords["p"], ["x", "y", "z", "time"])
        g = dataset.interp.group_map
        @test g["x"] != g["x_right"]
        @test g["z"] != g["z_outer"]
        # z_outer has one node more than z
        @test dataset.ds.dim["z"] == 8
        @test dataset.ds.dim["z_outer"] == 9
        # ground truth: Python u[0,0,0,0] and w[2,7,7,8] (time,x,y,z order)
        @test dataset.ds["u"][1, 1, 1, 1] == 7.582106781186548   # (z,y,x_right,time)
        @test dataset.ds["w"][9, 8, 8, 3] == 55.718675292651916  # (z_outer,y,x,time)
        close(dataset.ds)
    end

    @testset "mixed_spaces" begin
        dataset = open_fixture("mixed_spaces.zarr")
        check_zarr_store_basics(dataset)
        @test issetequal(dataset.variables, ["phi", "fx", "fy", "iteration"])
        check_time_coordinate(dataset, 2)
        # unequal staggered dimension lengths side by side
        @test dataset.ds.dim["y"] == 6
        @test dataset.ds.dim["y_outer"] == 7
        @test issetequal(dataset.var_coords["fy"], ["x", "y_outer", "time"])
        # ground truth: Python fy[1,7,6] (time,x,y_outer)
        @test dataset.ds["fy"][7, 8, 2] == 2.523049865434822     # (y_outer,x,time)
        close(dataset.ds)
    end

    @testset "1d_single_step" begin
        dataset = open_fixture("1d_single_step.zarr")
        check_zarr_store_basics(dataset)
        @test issetequal(dataset.variables, ["h", "iteration"])
        @test dataset.ds.dim["time"] == 1
        check_time_coordinate(dataset, 1)
        # ground truth: Python h[0,8] (time,x)
        @test dataset.ds["h"][9, 1] == -0.19509032201612836      # (x,time)
        @test Data.get_data(dataset, "h", ["x"], Dict("time" => 1))[9] ==
            -0.19509032201612836
        close(dataset.ds)
    end

    @testset "time_chunked_append" begin
        dataset = open_fixture("time_chunked_append.zarr")
        check_zarr_store_basics(dataset)
        @test issetequal(dataset.variables, ["c", "iteration"])
        # 5 steps written across two writer sessions (partial trailing chunk)
        @test dataset.ds.dim["time"] == 5
        check_time_coordinate(dataset, 5)
        @test size(Data.get_data(dataset, "c", ["x", "y"], Dict("time" => 5))) ==
            (8, 8)
        # The CF time axis ("seconds since 2020-01-01T00:00:00", whole-second
        # reference date — the fridom Writer trims the nanoseconds CFTime
        # cannot decode) decodes to real DateTimes, half-second steps included.
        @test eltype(dataset.ds["time"]) <: Union{Missing, Dates.DateTime}
        @test dataset.ds["time"][1] == Dates.DateTime(2020, 1, 1, 0, 0, 0)
        @test dataset.ds["time"][2] == Dates.DateTime(2020, 1, 1, 0, 0, 0, 500)
        @test dataset.ds["time"][5] == Dates.DateTime(2020, 1, 1, 0, 0, 2)
        # The undecoded raw values stay reachable for interpolation.
        @test Interpolate.convert_to_float64(dataset.ds, "time") ==
            [0.0, 0.5, 1.0, 1.5, 2.0]
        close(dataset.ds)
    end

    @testset "2d_scalar_v3 (zarr v3, detected but unsupported)" begin
        # Python-xarray-generated zarr format v3 store (zarr.json metadata).
        # The pinned Julia stack (ZarrDatasets 0.1.5 on Zarr.jl 0.9) cannot
        # read v3, so opening must fail with a clear, informative error
        # instead of Zarr.jl's cryptic "neither a ZArray nor a ZGroup".
        store = joinpath(ZARR_FIXTURE_DIR, "2d_scalar_v3.zarr")
        @test isfile(joinpath(store, "zarr.json"))       # v3 marker
        @test !isfile(joinpath(store, ".zgroup"))        # no v2 metadata
        @test Data.is_zarr_store(store)                  # still detected as zarr
        err = @test_throws ErrorException Data.CDFDataset([store])
        msg = sprint(showerror, err.value)
        @test occursin("zarr format v3", msg)
        @test occursin("not yet supported", msg)
        @test occursin(store, msg)
    end

    @testset "Batch output on a fixture" begin
        store = joinpath(ZARR_FIXTURE_DIR, "2d_scalar.zarr")
        out_dir = mktempdir()

        # --savefig writes a PNG
        args = parse_args(
            [store, "-v", "temp", "-x", "x", "-y", "y", "-p", "heatmap",
             "--savefig", "-s", "filename=\"temp_fixture.png\""],
            CDFViewer.get_arg_parser())
        cd(out_dir) do
            @suppress @test julia_main(parsed_args = args) == 0
        end
        @test isfile(joinpath(out_dir, "temp_fixture.png"))
        @test filesize(joinpath(out_dir, "temp_fixture.png")) > 0

        # --record writes an MP4 over the first three time steps
        args = parse_args(
            [store, "-v", "temp", "-x", "x", "-y", "y", "-p", "heatmap",
             "-a", "time", "--record",
             "-s", "filename=\"temp_fixture.mp4\", range=1:3"],
            CDFViewer.get_arg_parser())
        cd(out_dir) do
            @suppress @test julia_main(parsed_args = args) == 0
        end
        @test isfile(joinpath(out_dir, "temp_fixture.mp4"))
        @test filesize(joinpath(out_dir, "temp_fixture.mp4")) > 0
    end

end
