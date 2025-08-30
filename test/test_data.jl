using Test
using CDFViewer.Data
using NCDatasets
using DataStructures

import CDFViewer.Data as Data

"Helper: create a temporary NetCDF dataset with simple structure"
function make_temp_dataset()

    file = tempname() * ".nc"
    lon = collect(1:100)
    lat = collect(1:110)
    weird_dim = ["a", "ab", "abc"]  # a non-numeric dimension
    data = [Float32(i+j) for i = 1:length(lon), j = 1:length(lat)]
    lon_data = [Float32(i)*2 for i in lon]
    lat_data = [Float32(j)*3 for j in lat]

    ds = NCDataset(file,"c",attrib = OrderedDict("title" => "this is a test file")) do ds
        # Define the variable temperature. The dimension "lon" and "lat" with the
        # size 100 and 110 resp are implicitly created
        defVar(ds,"temperature",data,("lon","lat"), attrib = OrderedDict(
            "units" => "degree Celsius",
            "comments" => "this is a string attribute with Unicode Ω ∈ ∑ ∫ f(x) dx"
        ))
        defVar(ds,"lon",lon,("lon",), attrib = OrderedDict(
            "units" => "degrees_east",
            "long_name" => "Longitude"
        ))
        defVar(ds,"lat",lat,("lat",), attrib = OrderedDict(
            "units" => "degrees_north",
            "long_name" => "Latitude"
        ))
        defVar(ds,"weird_dim",weird_dim,("weird_dim",), attrib = OrderedDict(
            "units" => "n/a",
        ))
        defVar(ds,"mean_temp",lat_data, ("lat",), attrib = OrderedDict(
            "units" => "degree Celsius",
            "long_name" => "Mean Temperature"
        ))
        defVar(ds,"mean_temp2",lon_data, ("lon",), attrib = OrderedDict(
            "long_name" => "Mean Temperature 2"
        ))
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
    @test dataset.dimensions == ["lon", "lat", "weird_dim"]
    @test dataset.variables == ["temperature", "mean_temp", "mean_temp2"]

    # check labels
    @test Data.get_label(dataset, "temperature") == "temperature [degree Celsius]"
    @test Data.get_label(dataset, "lon") == "Longitude [degrees_east]"
    @test Data.get_label(dataset, "weird_dim") == "weird_dim [n/a]"

    # check dimension conversion
    for dim in dataset.dimensions
        vals = Data.get_dim_values(dataset, dim)
        @test vals isa Vector{Float64}
        @test length(vals) == length(dataset.ds[dim])
    end
end
