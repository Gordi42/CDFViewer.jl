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

end
