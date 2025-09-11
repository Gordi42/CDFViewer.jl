using Test
using ArgParse
using NCDatasets
using CDFViewer
using Suppressor

@testset "CDFViewer.jl" begin
    function create_lon_lat_data()::String
        fname = tempname() * ".nc"

        NCDataset(fname,"c") do ds
            defVar(ds,"temperature",[Float32(i+j) for i = 1:100, j = 1:110],("lon","lat"))
        end
        fname
    end

    @testset "is_headless" begin
        # while testing it should always be headless
        for (savefig, record) in ((false, false), (true, false), (false, true), (true, true))
            @test CDFViewer.is_headless(true, savefig, record) == true
        end
        # when not testing it should be headless only if savefig or record is true
        for (savefig, record) in ((true, false), (false, true), (true, true))
            @test CDFViewer.is_headless(false, savefig, record) == false
        end
        @test CDFViewer.is_headless(false, false, false) == true
    end

    @testset "julia_main with lat lon file" begin
        fname = create_lon_lat_data()
        args = parse_args([fname], CDFViewer.get_arg_parser())
    
        @suppress @test julia_main(parsed_args=args) == 0
    end
end
