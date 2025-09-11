using Test
using Suppressor
using GLMakie
using CDFViewer.Constants
using CDFViewer.Output
using ProgressMeter

vid_formats = Constants.VIDEO_FILE_FORMATS
fig_formats = Constants.IMAGE_FILE_FORMATS
all_formats = vcat(vid_formats, fig_formats)

@testset "Output.jl" begin

    @testset "check_extension" begin
        base = tempname()
        # Test when extension is missing
        @test Output.check_extension(base, vid_formats) == base * vid_formats[1]
        # Test when valid extension is present
        @test Output.check_extension(base * ".mp4", vid_formats) == base * ".mp4"
        # Test with non valid extension
        @test_warn "not recognized" begin
            @test Output.check_extension(base * ".avi", vid_formats) == base * vid_formats[1]
        end
        @test_warn "not recognized" begin
            @test Output.check_extension(base * ".jpg", fig_formats) == base * fig_formats[1]
        end
    end

    for mat in all_formats
        @testset "rename_filename with $mat" begin
            # Arrange: Create a temporary file to test with
            basename = tempname()
            tmp_file = basename * mat
            open(tmp_file, "w") do file
                write(file, "")
            end

            # Act: First rename should add (1)
            new1 = @suppress Output.rename_filename(tmp_file)

            # Assert: Check the new filename
            @test new1 == basename * "(1)" * mat

            # Arrange: Create the new1 file to simulate existing file
            open(new1, "w") do file
                write(file, "")
            end

            # Act: Second rename should add (2)
            new2 = @suppress Output.rename_filename(tmp_file)

            # Assert: Check the new filename
            @test new2 == basename * "(2)" * mat

            # Clean up
            rm(tmp_file; force=true)
            rm(new1; force=true)
            rm(new2; force=true)        
        end
    end

    @testset "check_filename" begin
        # Arrange: Create a temporary file to test with
        basename = tempname()
        tmp_file = basename * ".png"

        # Assert: check_filename should return the same name if file doesn't exist
        @test Output.check_filename(tmp_file) == tmp_file

        open(tmp_file, "w") do file
            write(file, "")
        end

        # Act & Assert: check_filename should warn and rename
        @test_warn "already exists" begin
            @test Output.check_filename(tmp_file) == basename * "(1).png"
        end

        # Clean up
        rm(tmp_file; force=true)
        rm(basename * "(1).png"; force=true)
    end

    @testset "move_file" begin
        # Arrange: Create a temporary source file
        src = tempname() * ".png"
        open(src, "w") do file
            write(file, "test")
        end

        dest = tempname() * ".png"

        # Act: Move the file
        Output.move_file(src, dest)

        # Assert: Check the file was moved
        @test !isfile(src)
        @test isfile(dest)

        # Arrange: Create the source file again to test renaming on move
        open(src, "w") do file
            write(file, "test")
        end

        # Act: Move the file again to the same destination
        @test_warn "already exists" begin
            Output.move_file(src, dest)
        end

        # Assert: Check the original destination exists and a renamed version exists
        @test isfile(dest)
        base, ext = splitext(dest)
        @test isfile("$(base)(1)$(ext)")

        # Clean up
        rm(dest; force=true)
        rm("$(base)(1)$(ext)"; force=true)
        rm(src; force=true)
    end

    @testset "savefig" begin
        # Arrange: Create a simple figure
        fig = Figure(size = (200, 200))
        lines!(Axis(fig[1, 1]), rand(10))
        filename = tempname() * ".png"
        base, ext = splitext(filename)

        # Assert: File should not exist yet
        @test !isfile(filename)
        @test !isfile("$(base)(1)$(ext)")
        @test !isfile("$(base)(2)$(ext)")
        @test !isfile("$(base)(3)$(ext)")

        # Act: Save the figure to a non-existing file
        @suppress Output.savefig(fig, Output.OutputSettings(filename))

        # Assert: Check the file was created
        @suppress @test isfile(filename)

        # Act: Save the figure again to test renaming
        @test_warn "already exists" begin
            Output.savefig(fig, Output.OutputSettings(filename))
        end

        # Assert: Check the renamed file was created
        @test isfile("$(base)(1)$(ext)")

        # Act: Save again, but without the extension
        @test_warn "already exists" begin
            Output.savefig(fig, Output.OutputSettings(base))
        end

        # Assert: Check the new renamed file was created with default extension
        @test isfile("$(base)(2)$(ext)")

        # Act: Save to a wrong extension
        @test_warn "File extension .jpg not recognized. Using .png instead." begin
            Output.savefig(fig, Output.OutputSettings(base * ".jpg"))
        end

        @test isfile("$(base)(3)$(ext)")

        # Clean up
        rm(filename; force=true)
        rm("$(base)(1)$(ext)"; force=true)
        rm("$(base)(2)$(ext)"; force=true)
        rm("$(base)(3)$(ext)"; force=true)
    end

    @testset "Record" begin
        # Arrange: Create a simple figure with a slider
        fig = Figure(size = (200, 200))
        ax = Axis(fig[1, 1])
        slider = Slider(fig[2, 1], range = 1:10)
        lines!(ax, @lift(rand($(slider.value))))
        file_name = tempname() * ".mp4"
        base, ext = splitext(file_name)

        # Assert: File should not exist yet
        @test !isfile(file_name)

        # Act: Record with no range specified
        @suppress Output.record_scene(fig, Output.OutputSettings(file_name), slider)

        # Assert: Check the file was created
        @test isfile(file_name)
        rm(file_name; force=true)

        # Act: Record with a specific range
        range = 3:7
        @suppress Output.record_scene(fig, Output.OutputSettings(file_name, range=range), slider)

        # Assert: Check the file was created
        @test isfile(file_name)
        rm(file_name; force=true)

        # Act: Record with all possible formats
        for fmt in vid_formats
            fname = base * fmt
            @suppress Output.record_scene(fig, Output.OutputSettings(fname, range=range), slider)

            # Assert: Check the file was created
            @test isfile(fname)
            rm(fname; force=true)
        end

        # Act: Record to a wrong extension
        @test_warn "File extension .avi not recognized. Using .mkv instead." begin
            Output.record_scene(fig, Output.OutputSettings(base * ".avi", range=range), slider)
        end

        # Assert: Check the new renamed file was created with default extension
        @test isfile(base * ".mkv")
        rm(base * ".mkv"; force=true)


        
        
    end

end