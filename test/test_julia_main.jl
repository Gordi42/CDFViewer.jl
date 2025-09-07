using Test
using NCDatasets
using CDFViewer

@testset "CDFViewer.jl" begin
    function create_lon_lat_data()::String
        fname = tempname() * ".nc"

        NCDataset(fname,"c") do ds
            defVar(ds,"temperature",[Float32(i+j) for i = 1:100, j = 1:110],("lon","lat"))
        end
        fname
    end

    @testset "julia_main no kwargs" begin
        @test julia_main(String[]; wait_for_ui=false) == 1  # No args provided
    end

    @testset "julia_main with lat lon file" begin
        fname = create_lon_lat_data()

        @test julia_main([fname]; wait_for_ui=false, visible=false) == 0
    end
end