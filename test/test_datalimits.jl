using Test
using CDFViewer.Data
using CDFViewer.DataLimits

@testset "DataLimits.jl" begin
    @testset "Hyperslab extrema" begin
        dataset = make_temp_dataset()
        ds = dataset.ds
        no_fix = Dict{String, Int}()

        # keeping every dimension scans the whole variable
        idx = DataLimits.scan_indexing(dataset, "3d_float",
                                       ["lon", "lat", "time"], no_fix)
        @test all(i -> i isa Colon, idx)
        vals = ds["3d_float"][:, :, :]
        @test DataLimits.hyperslab_extrema(dataset, "3d_float", idx) ==
            (minimum(vals), maximum(vals))

        # fixed dimensions restrict the scan to their slice
        sel = Dict("lon" => 1, "lat" => 1, "time" => 2)
        idx = DataLimits.scan_indexing(dataset, "3d_float", ["lon", "lat"], sel)
        @test idx == [Colon(), Colon(), 2]
        slab = ds["3d_float"][:, :, 2]
        @test DataLimits.hyperslab_extrema(dataset, "3d_float", idx) ==
            (minimum(slab), maximum(slab))

        # a fully fixed hyperslab is a single value
        idx = DataLimits.scan_indexing(dataset, "3d_float", String[], sel)
        lo, hi = DataLimits.hyperslab_extrema(dataset, "3d_float", idx)
        @test lo == hi == ds["3d_float"][1, 1, 2]

        # an aborted scan returns nothing
        idx = DataLimits.scan_indexing(dataset, "3d_float",
                                       ["lon", "lat", "time"], no_fix)
        @test DataLimits.hyperslab_extrema(dataset, "3d_float", idx;
                                           abort = () -> true) === nothing

        # non-numeric variables have no extrema
        sidx = DataLimits.scan_indexing(dataset, "string_var",
                                        ["string_dim"], no_fix)
        @test DataLimits.hyperslab_extrema(dataset, "string_var", sidx) ===
            nothing

        # element counts are known before reading anything
        idx = DataLimits.scan_indexing(dataset, "3d_float",
                                       ["lon", "lat", "time"], no_fix)
        @test DataLimits.hyperslab_elements(dataset, "3d_float", idx) ==
            5 * 7 * 4
        idx = DataLimits.scan_indexing(dataset, "3d_float", ["lon", "lat"], sel)
        @test DataLimits.hyperslab_elements(dataset, "3d_float", idx) == 5 * 7

        close(ds)
    end

    @testset "Several variables in lockstep" begin
        dataset = make_vector_temp_dataset()
        ds = dataset.ds
        no_fix = Dict{String, Int}()
        idx = DataLimits.scan_indexing(dataset, "u", ["lon", "lat", "time"],
                                       no_fix)

        u = ds["u"][:, :, :]
        v = ds["v"][:, :, :]
        # one variable still tracks its own signed values
        @test DataLimits.hyperslab_extrema(dataset, ["u"], idx) ==
            (minimum(u), maximum(u))
        # two are reduced element by element -- the magnitude, not the
        # range of either component
        @test DataLimits.hyperslab_extrema(dataset, ["u", "v"], idx) ==
            extrema(hypot.(u, v))
        # an explicit combiner is honoured
        @test DataLimits.hyperslab_extrema(dataset, ["u", "v"], idx;
                                           combine = (a, b) -> a + b) ==
            extrema(u .+ v)

        # the combiner sees each element's components, in order
        @test DataLimits.scan_value(-3.0) == -3.0
        @test DataLimits.scan_value(3.0, 4.0) == 5.0

        # every variable costs its own hyperslab
        @test DataLimits.hyperslab_elements(dataset, ["u"], idx) ==
            12 * 8 * 3
        @test DataLimits.hyperslab_elements(dataset, ["u", "v"], idx) ==
            2 * 12 * 8 * 3

        # components of different shapes cannot share one indexing
        @test DataLimits.hyperslab_extrema(dataset, ["u", "vmix"], idx) ===
            nothing
        @test DataLimits.hyperslab_extrema(dataset, String[], idx) === nothing

        # a fixed dimension restricts every component alike
        sel = Dict("lon" => 1, "lat" => 1, "time" => 2)
        idx = DataLimits.scan_indexing(dataset, "u", ["lon", "lat"], sel)
        @test DataLimits.hyperslab_extrema(dataset, ["u", "v"], idx) ==
            extrema(hypot.(u[:, :, 2], v[:, :, 2]))

        # a fully fixed hyperslab is one element out of each component
        idx = DataLimits.scan_indexing(dataset, "u", String[], sel)
        @test DataLimits.hyperslab_extrema(dataset, ["u", "v"], idx) ==
            (hypot(u[1, 1, 2], v[1, 1, 2]), hypot(u[1, 1, 2], v[1, 1, 2]))

        close(ds)
    end

    @testset "Missing and NaN values" begin
        file = tempname() * ".nc"
        NCDataset(file, "c") do ds
            defVar(ds, "x", collect(1.0:4.0), ("x",))
            defVar(ds, "t", collect(1.0:3.0), ("t",))
            v = defVar(ds, "u", Float64, ("x", "t"), fillvalue = -999.0)
            v[:, 1] = [1.0, 2.0, NaN, 4.0]
            v[:, 2] = [missing, missing, missing, missing]
            v[:, 3] = [0.5, 6.0, 2.0, 3.0]
        end
        dataset = Data.CDFDataset([file])
        idx = DataLimits.scan_indexing(dataset, "u", ["x", "t"],
                                       Dict{String, Int}())
        @test DataLimits.hyperslab_extrema(dataset, "u", idx) == (0.5, 6.0)

        # a slab with no finite value yields nothing
        idx = DataLimits.scan_indexing(dataset, "u", ["x"], Dict("t" => 2))
        @test DataLimits.hyperslab_extrema(dataset, "u", idx) === nothing
        close(dataset.ds)
    end
end
