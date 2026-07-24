using Test
using CDFViewer.RescaleUnits
using NCDatasets

@testset "RescaleUnits.jl" begin
    @testset "get_standard_name" begin
        # Arrange: Standard test dataset
        ds = make_temp_dataset().ds

        # Act & Assert: Variable dimensions
        @test RescaleUnits.get_standard_name("lon", ds) == "longitude"
        @test RescaleUnits.get_standard_name("lat", ds) == "latitude"
        @test RescaleUnits.get_standard_name("time", ds) == "time"

        # Act & Assert: Dimension with no variable
        @test RescaleUnits.get_standard_name("untaken", ds) == "untaken"

        # Act & Assert: Non-existing dimension
        @test RescaleUnits.get_standard_name("non_existing", ds) == "non_existing"

        # Cleanup
        close(ds)
    end

    @testset "get_remapped_unit" begin
        @testset "Standard Data" begin
            # Arrange: Standard test dataset
            ds = make_temp_dataset().ds

            # Act & Assert: Variable with no unit
            @test RescaleUnits.get_remapped_unit(ds, "1d_float") == ""

            # Act & Assert: Variable with unit "n/a"
            @test RescaleUnits.get_remapped_unit(ds, "only_unit") == "n/a"

            # Act & Assert: Dimension with no variable
            @test RescaleUnits.get_remapped_unit(ds, "untaken") == ""

            # Act & Assert: Non-existing dimension
            @test RescaleUnits.get_remapped_unit(ds, "non_existing") == ""

            # Cleanup
            close(ds)
        end

        @testset "Geographical Data in Radian" begin
            # Arrange: Unstructured dataset
            ds = make_unstructured_temp_dataset().ds

            # Act & Assert: Longitude and Latitude should have radian units
            @test RescaleUnits.get_unit(ds, "clon") == "radian"
            @test RescaleUnits.get_unit(ds, "clat") == "radian"

            # Act & Assert: Longitude and Latitude should be remapped to degrees
            @test RescaleUnits.get_remapped_unit(ds, "clon") == "degrees"
            @test RescaleUnits.get_remapped_unit(ds, "clat") == "degrees"

            # Cleanup
            close(ds)
        end

        @testset "Geographical Data in Degrees" begin
            # Arrange: Semi-unstructured dataset
            ds = make_semi_unstructured_temp_dataset().ds

            # Act & Assert: Longitude and Latitude should have degree units
            @test RescaleUnits.get_unit(ds, "lon") == "degrees"
            @test RescaleUnits.get_unit(ds, "lat") == "degrees"

            # Act & Assert: Longitude and Latitude should remain in degrees
            @test RescaleUnits.get_remapped_unit(ds, "lon") == "degrees"
            @test RescaleUnits.get_remapped_unit(ds, "lat") == "degrees"

            # Cleanup
            close(ds)
        end


    end

    @testset "Unit Conversion Functions" begin
        @testset "radians_to_degrees" begin
            @test isapprox(RescaleUnits.radians_to_degrees(0.0), 0.0)
            @test isapprox(RescaleUnits.radians_to_degrees(-π/2), -90.0)
            @test isapprox(RescaleUnits.radians_to_degrees(π/2), 90.0)
            @test isapprox(RescaleUnits.radians_to_degrees(π), 180.0)
            @test isapprox(RescaleUnits.radians_to_degrees(3π/2), 270.0)
            @test isapprox(RescaleUnits.radians_to_degrees(2π), 360.0)
        end
    end

    @testset "get_transformation_function" begin
        @testset "Standard Data" begin
            # Arrange: Standard test dataset
            ds = make_temp_dataset().ds

            # Act & Assert: Variable with no unit
            @test RescaleUnits.get_transformation_function(ds, "lon") == identity

            # Act & Assert: Variable with unit "n/a"
            @test RescaleUnits.get_transformation_function(ds, "only_unit") == identity

            # Act & Assert: Dimension with no variable
            @test RescaleUnits.get_transformation_function(ds, "untaken") == identity

            # Act & Assert: Non-existing dimension
            @test RescaleUnits.get_transformation_function(ds, "non_existing") == identity

            # Cleanup
            close(ds)
        end

        @testset "Geographical Data in Radian" begin
            # Arrange: Unstructured dataset
            ds = make_unstructured_temp_dataset().ds

            # Act & Assert: Transformation function should be radians_to_degrees
            @test RescaleUnits.get_transformation_function(ds, "clon") == RescaleUnits.radians_to_degrees
            @test RescaleUnits.get_transformation_function(ds, "clat") == RescaleUnits.radians_to_degrees

            # Cleanup
            close(ds)
        end

        @testset "Geographical Data in Degrees" begin
            # Arrange: Semi-unstructured dataset
            ds = make_semi_unstructured_temp_dataset().ds

            # Act & Assert: Transformation function should be identity
            @test RescaleUnits.get_transformation_function(ds, "lon") == identity
            @test RescaleUnits.get_transformation_function(ds, "lat") == identity

            # Cleanup
            close(ds)
        end

    end

    @testset "Display units" begin
        @testset "Unit lookup" begin
            # Act & Assert: canonical spellings, aliases, case-insensitivity
            @test RescaleUnits.display_unit("km").canonical == "km"
            @test RescaleUnits.display_unit("Kilometers").canonical == "km"
            @test RescaleUnits.display_unit("metre").canonical == "m"
            @test RescaleUnits.display_unit(" hPa ").canonical == "hPa"
            @test RescaleUnits.display_unit("hours").canonical == "h"

            # Act & Assert: unknown spellings
            @test RescaleUnits.display_unit("furlong") === nothing
            @test RescaleUnits.display_unit("") === nothing
            @test RescaleUnits.display_unit("degrees_east") === nothing

            # Act & Assert: every canonical name resolves to itself
            for name in RescaleUnits.display_unit_names()
                @test RescaleUnits.display_unit(name).canonical == name
            end
        end

        @testset "Conversion factors" begin
            # Act & Assert: within-family factors
            @test RescaleUnits.display_factor("m", "km") == 1e-3
            @test RescaleUnits.display_factor("km", "m") == 1e3
            @test RescaleUnits.display_factor("cm", "mm") == 10.0
            @test RescaleUnits.display_factor("s", "min") == 1 / 60
            @test RescaleUnits.display_factor("seconds", "h") == 1 / 3600
            @test RescaleUnits.display_factor("Pa", "bar") == 1e-5
            @test RescaleUnits.display_factor("dbar", "hPa") == 100.0
            @test RescaleUnits.display_factor("m", "m") == 1.0

            # Act & Assert: sub-second units and the Julian year
            @test RescaleUnits.display_factor("s", "ms") == 1e3
            @test RescaleUnits.display_factor("us", "s") == 1e-6
            @test RescaleUnits.display_unit("microseconds").canonical == "µs"
            @test RescaleUnits.display_factor("s", "yr") == 1 / 3.15576e7
            @test RescaleUnits.display_unit("years").canonical == "yr"
            @test RescaleUnits.display_factor("d", "yr") == 1 / 365.25

            # Act & Assert: cross-family and unknown units do not convert
            @test RescaleUnits.display_factor("m", "s") === nothing
            @test RescaleUnits.display_factor("m", "furlong") === nothing
            @test RescaleUnits.display_factor("", "km") === nothing
            @test RescaleUnits.display_factor(
                "days since 2000-01-01", "d") === nothing
        end

        @testset "Automatic unit choice" begin
            # Act & Assert: the largest unit keeping the maximum >= 1
            @test RescaleUnits.auto_display_unit("s", 5e6) == "d"
            @test RescaleUnits.auto_display_unit("s", 4e8) == "yr"
            @test RescaleUnits.auto_display_unit("s", 90.0) == "min"
            @test RescaleUnits.auto_display_unit("s", 30.0) == "s"
            @test RescaleUnits.auto_display_unit("m", 2.5e6) == "km"
            @test RescaleUnits.auto_display_unit("days", 0.5) == "h"

            # Act & Assert: below every family unit, the smallest one wins
            @test RescaleUnits.auto_display_unit("s", 0.5) == "ms"
            @test RescaleUnits.auto_display_unit("s", 1e-12) == "ns"

            # Act & Assert: unknown units or degenerate magnitudes pick nothing
            @test RescaleUnits.auto_display_unit("furlong", 10.0) === nothing
            @test RescaleUnits.auto_display_unit("s", 0.0) === nothing
            @test RescaleUnits.auto_display_unit("s", NaN) === nothing
            @test RescaleUnits.auto_display_unit("s", Inf) === nothing
        end
    end

end
