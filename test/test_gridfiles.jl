using Test

using DataStructures
using NCDatasets
using CDFViewer
using CDFViewer.GridFiles
using CDFViewer.Data

@testset "GridFiles.jl" begin

    NCELLS = 60
    NVERTS = 110

    function make_data_file(dir::String;
            uuid::Union{String, Nothing}="deadbeef-1234",
            grid_number::Bool=true,
            uri::Union{String, Nothing}=nothing,
            ncells::Int=NCELLS)::String
        attribs = OrderedDict{String, Any}()
        uuid === nothing || (attribs["uuidOfHGrid"] = uuid)
        grid_number && (attribs["number_of_grid_used"] = Int32(42))
        uri === nothing || (attribs["grid_file_uri"] = uri)
        data_file = joinpath(dir, "data.nc")
        NCDataset(data_file, "c", attrib=attribs) do ds
            defVar(ds, "time", collect(1:3), ("time",),
                attrib=Dict("units" => "days since 2000-01-01 00:00:00"))
            defVar(ds, "temp", rand(ncells, 3), ("ncells", "time"),
                attrib=Dict("coordinates" => "clat clon", "units" => "K"))
        end
        data_file
    end

    function make_grid_file(dir::String;
            uuid::Union{String, Nothing}="deadbeef-1234",
            name::String="icon_grid_0042_R02B04_G.nc",
            ncells::Int=NCELLS)::String
        grid_file = joinpath(dir, name)
        attribs = OrderedDict{String, Any}("number_of_grid_used" => Int32(42))
        uuid === nothing || (attribs["uuidOfHGrid"] = uuid)
        NCDataset(grid_file, "c", attrib=attribs) do ds
            defVar(ds, "clon", rand(ncells) .* 2 .- 1, ("cell",),
                attrib=Dict("units" => "radian", "standard_name" => "longitude"))
            defVar(ds, "clat", rand(ncells) .- 0.5, ("cell",),
                attrib=Dict("units" => "radian", "standard_name" => "latitude"))
            defVar(ds, "vlon", rand(NVERTS), ("vertex",),
                attrib=Dict("units" => "radian", "standard_name" => "longitude"))
        end
        grid_file
    end

    "Config file pointing the grid search at the given directories."
    function with_config(f::Function, dirs::Vector{String}; download::Bool=false)
        config_file = tempname() * ".toml"
        open(config_file, "w") do io
            println(io, "[grid]")
            println(io, "search = true")
            println(io, "search_dirs = [", join(repr.(dirs), ", "), "]")
            println(io, "download = ", download)
        end
        try
            withenv(f, "CDFVIEWER_CONFIG" => config_file)
        finally
            rm(config_file, force=true)
        end
    end

    "Config pointing nowhere, so searches never leave the data directory."
    with_isolated_config(f::Function) = with_config(f, String[])

    @testset "missing_coordinates" begin
        dir = mktempdir()
        data_file = make_data_file(dir)
        NCDataset(data_file) do ds
            @test sort(GridFiles.missing_coordinates(ds)) == ["clat", "clon"]
            @test GridFiles.needs_grid_file(ds)
        end

        # Nothing missing in a self-contained file
        grid_file = make_grid_file(dir)
        NCDataset(grid_file) do ds
            @test isempty(GridFiles.missing_coordinates(ds))
            @test !GridFiles.needs_grid_file(ds)
        end
    end

    @testset "config loading" begin
        config_file = tempname() * ".toml"
        open(config_file, "w") do io
            print(io, """
            [grid]
            search = false
            search_dirs = ["/some/dir", "~/grids"]
            download = true
            download_dir = "/cache/dir"
            """)
        end
        config = GridFiles.load_config(config_file)
        @test config.search == false
        @test config.search_dirs == ["/some/dir", expanduser("~/grids")]
        @test config.download == true
        @test config.download_dir == "/cache/dir"
        rm(config_file)

        # Missing file falls back to defaults
        default = GridFiles.load_config(tempname())
        @test default.search == true
        @test isempty(default.search_dirs)
        @test default.download == false
    end

    @testset "merge_grid_file" begin
        dir = mktempdir()
        data_file = make_data_file(dir)
        grid_file = make_grid_file(dir)

        data_ds = NCDataset(data_file)
        merged = GridFiles.merge_grid_file(data_ds, grid_file)
        @test merged isa GridFiles.MergedDataset

        # Injected coordinates appear under the data file's dimension names
        @test haskey(merged, "clon")
        @test haskey(merged, "clat")
        @test collect(NCDatasets.dimnames(merged["clon"])) == ["ncells"]
        @test length(merged["clon"][:]) == NCELLS
        @test merged["clon"].attrib["standard_name"] == "longitude"
        # Data variables and dimensions pass through
        @test haskey(merged, "temp")
        @test merged.dim["ncells"] == NCELLS
        # The vertex variable is not referenced by any data variable
        @test !haskey(merged, "vlon")
        close(merged)
    end

    @testset "uuid mismatch is rejected in search mode" begin
        dir = mktempdir()
        data_file = make_data_file(dir, uuid="deadbeef-1234")
        grid_file = make_grid_file(dir, uuid="0therun1d-5678")

        NCDataset(data_file) do data_ds
            @test GridFiles.merge_grid_file(data_ds, grid_file) === nothing
            # Explicit grid file: warn but merge
            @test_warn "uuidOfHGrid mismatch" begin
                merged = GridFiles.merge_grid_file(data_ds, grid_file, explicit=true)
                @test merged isa GridFiles.MergedDataset
                close(merged.grid_ds)
            end
        end
    end

    @testset "dimension size mismatch is rejected" begin
        dir = mktempdir()
        data_file = make_data_file(dir, ncells=NCELLS)
        grid_file = make_grid_file(dir, ncells=NCELLS + 7)

        NCDataset(data_file) do data_ds
            @test_warn "Cannot attach grid coordinate" begin
                @test GridFiles.merge_grid_file(data_ds, grid_file) === nothing
            end
        end
    end

    @testset "find_grid_file" begin
        data_dir = mktempdir()
        grid_dir = mktempdir()
        config = GridFiles.GridConfig(true, [grid_dir], false, tempname())

        # 2. filename pattern icon_grid_<NNNN>_*.nc
        data_file = make_data_file(data_dir)
        grid_file = make_grid_file(grid_dir)
        NCDataset(data_file) do ds
            @test GridFiles.find_grid_file(ds, data_dir, config) == grid_file
        end

        # 1. URI basename beats the pattern
        named = make_grid_file(grid_dir, name="my_custom_grid.nc")
        data_uri = make_data_file(data_dir,
            uri="http://icon-downloads.mpimet.mpg.de/grids/public/mpim/0042/my_custom_grid.nc")
        NCDataset(data_uri) do ds
            @test GridFiles.find_grid_file(ds, data_dir, config) == named
        end

        # 3. uuid scan (no uri, no grid number attribute)
        data_uuid_only = make_data_file(data_dir, grid_number=false)
        renamed = make_grid_file(grid_dir, name="icon_gridfile_someone_renamed.nc")
        rm(grid_file)  # remove the pattern match, force the uuid scan
        rm(named)
        NCDataset(data_uuid_only) do ds
            @test GridFiles.find_grid_file(ds, data_dir, config) == renamed
        end

        # grid file right next to the data file is found without any config
        no_config = GridFiles.GridConfig(true, String[], false, tempname())
        local_grid = make_grid_file(data_dir)
        NCDataset(data_file) do ds
            @test GridFiles.find_grid_file(ds, data_dir, no_config) == local_grid
        end

        # nothing found
        empty_dir = mktempdir()
        NCDataset(make_data_file(empty_dir)) do ds
            @test GridFiles.find_grid_file(ds, empty_dir,
                GridFiles.GridConfig(true, String[], false, tempname())) === nothing
        end
    end

    @testset "CDFDataset integration" begin
        dir = mktempdir()
        data_file = make_data_file(dir)
        grid_file = make_grid_file(dir)

        # Explicit grid file
        with_isolated_config() do
            dataset = Data.CDFDataset([data_file], grid_file=grid_file)
            @test "clon" in dataset.coordinates
            @test "clat" in dataset.coordinates
            @test sort(dataset.var_coords["temp"]) == ["clat", "clon", "time"]
            # clon/clat share the ncells dimension -> paired for interpolation
            @test dataset.paired_coords["clon"] == ["clat"]
            # radian units are remapped for plotting
            @test CDFViewer.RescaleUnits.get_remapped_unit(dataset.ds, "clon") == "degrees"
            close(dataset.ds)
        end

        # Automatic search via config
        grid_dir = mktempdir()
        searched_grid = make_grid_file(grid_dir)
        isolated = make_data_file(mktempdir())
        with_config([grid_dir]) do
            dataset = Data.CDFDataset([isolated])
            @test "clon" in dataset.coordinates
            @test dataset.ds isa GridFiles.MergedDataset
            @test dataset.ds.grid_path == searched_grid
            close(dataset.ds)
        end

        # Search disabled -> falls back to plain dataset
        with_config([grid_dir]) do
            dataset = Data.CDFDataset([isolated], grid_search=false)
            @test "clon" ∉ dataset.coordinates
            @test !(dataset.ds isa GridFiles.MergedDataset)
            close(dataset.ds)
        end
    end

    @testset "multi-file datasets (MFDataset regression)" begin
        # Aggregating multiple files returns an MFDataset, which is not an
        # NCDataset - CDFDataset must accept it.
        dir = mktempdir()
        files = String[]
        for (i, trange) in enumerate((1:3, 4:6))
            file = joinpath(dir, "part$i.nc")
            NCDataset(file, "c") do ds
                defDim(ds, "time", Inf)
                defVar(ds, "time", collect(trange), ("time",),
                    attrib=Dict("units" => "days since 2000-01-01 00:00:00"))
                defVar(ds, "x", collect(1.0:5.0), ("x",))
                v = defVar(ds, "var", Float64, ("x", "time"))
                v[:, :] = rand(5, length(trange))
            end
            push!(files, file)
        end
        with_isolated_config() do
            dataset = Data.CDFDataset(files)
            @test "var" in dataset.variables
            @test dataset.ds.dim["time"] == 6
            close(dataset.ds)
        end
    end

    @testset "command line interface" begin
        using ArgParse
        parser = CDFViewer.get_arg_parser()
        args = parse_args(["file.nc", "--grid", "grid.nc"], parser)
        @test args["grid"] == "grid.nc"
        @test args["no-grid-search"] == false
        args = parse_args(["file.nc", "--no-grid-search"], parser)
        @test args["grid"] == ""
        @test args["no-grid-search"] == true
    end

end
