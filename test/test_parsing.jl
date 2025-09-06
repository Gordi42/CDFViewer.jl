using Test
using CDFViewer.Parsing

@testset "Parsing.jl" begin

    @testset "Single Values" begin
        # Symbols
        @test Parsing.parse_kwargs("colormap=:viridis") == Dict(:colormap => :viridis)

        # Numeric
        @test Parsing.parse_kwargs("linewidth=2") == Dict(:linewidth => 2)
        @test Parsing.parse_kwargs("threshold=3.14") == Dict(:threshold => 3.14)
        @test Parsing.parse_kwargs("threshold=2e-3") == Dict(:threshold => 2e-3)
        @test Parsing.parse_kwargs("threshold=-1E+5") == Dict(:threshold => -1E+5)

        # Strings
        @test Parsing.parse_kwargs("title=\"My Plot\"") == Dict(:title => "My Plot")
        @test Parsing.parse_kwargs("xlabel='X Axis'") == Dict(:xlabel => "X Axis")

        # Booleans
        @test Parsing.parse_kwargs("show_legend=true") == Dict(:show_legend => true)
        @test Parsing.parse_kwargs("show_legend=false") == Dict(:show_legend => false)

        # Empty input
        @test Parsing.parse_kwargs("") == Dict{Symbol, Any}()
    end

    @testset "Arrays and Tuples" begin
        # Arrays
        @test Parsing.parse_kwargs("levels=[1, 2, 4]") == Dict(:levels => [1, 2, 4])
        @test Parsing.parse_kwargs("colors=[\"red\", \"green\", \"blue\"]") == Dict(:colors => ["red", "green", "blue"])
        @test Parsing.parse_kwargs("mixed=[1, :a, \"text\"]") == Dict(:mixed => [1, :a, "text"])
        @test Parsing.parse_kwargs("spaces=[1.0, 2.5,3.75 ]") == Dict(:spaces => [1.0, 2.5, 3.75])
        @test Parsing.parse_kwargs("empty_array=[]") == Dict(:empty_array => [])

        # Tuples
        @test Parsing.parse_kwargs("colorrange=(0, 1)") == Dict(:colorrange => (0, 1))
        @test Parsing.parse_kwargs("range=(-1.0,1.0)") == Dict(:range => (-1.0, 1.0))
        @test Parsing.parse_kwargs("mixed_tuple=(2e-3, :b, \"label\")") == Dict(:mixed_tuple => (2e-3, :b, "label"))
    end

    @testset "Complex Cases" begin
        @test Parsing.parse_kwargs("colormap=:viridis , linewidth=2, colorrange=(0,1)") ==
              Dict(:colormap => :viridis, :linewidth => 2, :colorrange => (0, 1))

        @test Parsing.parse_kwargs("colormap=:viridis , levels=[1, 2, 4], colorrange=(0, 1, 3)") ==
              Dict(:colormap => :viridis, :levels => [1, 2, 4], :colorrange => (0, 1, 3))

        @test Parsing.parse_kwargs("range=(1e-3, 2E+5), data=[1, :a, \"text\"]") ==
              Dict(:range => (1e-3, 2E+5), :data => [1, :a, "text"])

        @test Parsing.parse_kwargs("""colormap = :viridis, xlabel = "Time, (s)" """) ==
              Dict(:colormap => :viridis, :xlabel => "Time, (s)")
    end
end