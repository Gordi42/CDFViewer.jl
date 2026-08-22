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

    @testset "apply_settings_string!" begin
        settings = Output.OutputSettings("output")

        # Act: every field the command line may name
        Output.apply_settings_string!(
            settings,
            "filename=\"movie.mp4\", framerate=12, px_per_unit=2, range=2:8, " *
            "overwrite=false")

        # Assert
        @test settings.filename == "movie.mp4"
        @test settings.framerate == 12
        @test settings.px_per_unit == 2
        @test settings.range == 2:8
        @test settings.overwrite == false

        # Act & Assert: an empty line changes nothing
        Output.apply_settings_string!(settings, "")
        @test settings.filename == "movie.mp4"

        # Act & Assert: a field that does not exist is named back
        @test_warn "Unknown OutputSettings property: dpi" begin
            Output.apply_settings_string!(settings, "dpi=300")
        end

        # Act & Assert: so is a value the field cannot take
        @test_warn "Failed to set OutputSettings.framerate" begin
            Output.apply_settings_string!(settings, "framerate=\"fast\"")
        end
        @test settings.framerate == 12
    end

    @testset "settings_string" begin
        # Assert: settings a fresh start would reproduce write nothing
        settings = Output.OutputSettings("demo")
        @test Output.settings_string(settings; filename = "demo") == ""

        # Assert: a name that was not derived from the data file travels
        @test Output.settings_string(settings; filename = "other") ==
            "filename=\"demo\""

        # Act: change everything else
        settings.framerate = 12
        settings.px_per_unit = 2
        settings.range = 2:8
        settings.overwrite = false

        # Assert
        @test Output.settings_string(settings; filename = "demo") ==
            "framerate=12, px_per_unit=2, range=2:8, overwrite=false"

        # Assert: the working directory is the process' own and stays out
        settings.work_dir = tempdir()
        @test !occursin("work_dir", Output.settings_string(settings; filename = "demo"))

        # Assert: what it writes reads back as what it was given
        parsed = Output.apply_settings_string!(
            Output.OutputSettings("demo"),
            Output.settings_string(settings; filename = "demo"))
        @test parsed.framerate == settings.framerate
        @test parsed.px_per_unit == settings.px_per_unit
        @test parsed.range == settings.range
        @test parsed.overwrite == settings.overwrite
    end

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
        @test Output.check_filename(tmp_file; overwrite=false) == tmp_file

        open(tmp_file, "w") do file
            write(file, "")
        end

        # Act & Assert: a taken name is kept, and the overwrite is announced
        @test_warn "being overwritten" begin
            @test Output.check_filename(tmp_file) == tmp_file
        end
        @test !isfile(basename * "(1).png")

        # Act & Assert: overwrite=false steps on to the next free name
        @test_warn "Rename to avoid overwriting" begin
            @test Output.check_filename(tmp_file; overwrite=false) ==
                basename * "(1).png"
        end

        # Clean up
        rm(tmp_file; force=true)
        rm(basename * "(1).png"; force=true)
    end

    @testset "move_file" begin
        # Arrange: Create a temporary source file
        src = tempname() * ".png"
        open(src, "w") do file
            write(file, "first")
        end

        dest = tempname() * ".png"
        base, ext = splitext(dest)

        # Act: Move the file
        Output.move_file(src, dest)

        # Assert: Check the file was moved
        @test !isfile(src)
        @test isfile(dest)

        # Arrange: A second file for the same destination, told apart by
        # its contents
        open(src, "w") do file
            write(file, "second")
        end

        # Act: Move it onto the destination that is now taken
        @test_warn "being overwritten" begin
            Output.move_file(src, dest)
        end

        # Assert: the destination holds the newer file, and no numbered
        # copy was left beside it
        @test !isfile(src)
        @test read(dest, String) == "second"
        @test !isfile("$(base)(1)$(ext)")

        # Arrange: a third file, for the non-overwriting path
        open(src, "w") do file
            write(file, "third")
        end

        # Act: Move it with the numbering asked for
        @test_warn "Rename to avoid overwriting" begin
            Output.move_file(src, dest; overwrite=false)
        end

        # Assert: the destination is untouched and the new file sits beside it
        @test read(dest, String) == "second"
        @test read("$(base)(1)$(ext)", String) == "third"

        # Clean up
        rm(dest; force=true)
        rm("$(base)(1)$(ext)"; force=true)
        rm(src; force=true)
    end

    @testset "savefig" begin
        # Arrange: Two figures that cannot render to the same bytes, so a
        # file written over can be told from one that was left alone
        fig = Figure(size = (200, 200))
        lines!(Axis(fig[1, 1]), zeros(10))
        other = Figure(size = (200, 200))
        lines!(Axis(other[1, 1]), collect(1:10))
        filename = tempname() * ".png"
        base, ext = splitext(filename)

        # Assert: File should not exist yet
        @test !isfile(filename)
        @test !isfile("$(base)(1)$(ext)")

        # Act: Save the figure to a non-existing file
        @suppress Output.savefig(fig, Output.OutputSettings(filename))

        # Assert: Check the file was created
        @suppress @test isfile(filename)
        fig_bytes = read(filename)

        # Act: Save the other figure under the same name
        @test_warn "being overwritten" begin
            Output.savefig(other, Output.OutputSettings(filename))
        end

        # Assert: the name holds the newer figure, and nothing was left
        # beside it -- re-running a save refreshes the file it named
        other_bytes = read(filename)
        @test other_bytes != fig_bytes
        @test !isfile("$(base)(1)$(ext)")

        # Act: Save again, but without the extension
        @test_warn "being overwritten" begin
            Output.savefig(fig, Output.OutputSettings(base))
        end

        # Assert: the derived extension lands on the same file
        @test read(filename) != other_bytes
        @test !isfile("$(base)(1)$(ext)")

        # Act: Save to a wrong extension
        @test_warn "File extension .jpg not recognized. Using .png instead." begin
            Output.savefig(other, Output.OutputSettings(base * ".jpg"))
        end

        # Assert: the derived extension lands on the same file too
        @test read(filename) != fig_bytes
        @test !isfile("$(base)(1)$(ext)")

        # Act: Save with the numbering asked for instead
        @test_warn "Rename to avoid overwriting" begin
            Output.savefig(fig, Output.OutputSettings(filename; overwrite=false))
        end

        # Assert: the taken name is untouched and the figure sits beside it
        @test isfile("$(base)(1)$(ext)")
        @test read("$(base)(1)$(ext)") != read(filename)

        # Clean up
        rm(filename; force=true)
        rm("$(base)(1)$(ext)"; force=true)
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

        # Act: Record over it again, as a re-run of the same command would
        @test_warn "being overwritten" begin
            Output.record_scene(fig, Output.OutputSettings(file_name, range=range), slider)
        end

        # Assert: the name still points at the recording just made, rather
        # than at the first one with the new take parked beside it
        @test isfile(file_name)
        @test !isfile("$(base)(1)$(ext)")
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