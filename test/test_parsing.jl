using Test
using Makie
using GLMakie
import Colors
import Dates
using CDFViewer.Parsing

# a name that exists here and nowhere else, to show that keyword values are
# not evaluated in the calling module
parsing_test_probe(x) = x

@testset "Parsing.jl" begin

    @testset "Single Values" begin
        # Symbols
        @test Parsing.parse_kwargs("colormap=:viridis") == Dict(:colormap => :viridis)

        # Numeric
        @test Parsing.parse_kwargs("linewidth=2") == Dict(:linewidth => 2)
        @test Parsing.parse_kwargs("linewidth=2")[:linewidth] isa Int
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

    @testset "Special Values" begin
        @test Parsing.parse_kwargs("flag=true, option=false, value=nothing") ==
              Dict(:flag => true, :option => false, :value => nothing)
        @test Parsing.parse_kwargs("func=identity") == Dict(:func => identity)
        @test Parsing.parse_kwargs("log_func=log") == Dict(:log_func => log)
        @test Parsing.parse_kwargs("log2_func=log2") == Dict(:log2_func => log2)
        @test Parsing.parse_kwargs("log10_func=log10") == Dict(:log10_func => log10)
        @test Parsing.parse_kwargs("sqrt_func=sqrt") == Dict(:sqrt_func => sqrt)
        @test Parsing.parse_kwargs("sqrt_func=1:10") == Dict(:sqrt_func => 1:10)
        @test Parsing.parse_kwargs("sqrt_func=1:3:10") == Dict(:sqrt_func => 1:3:10)

        @test Parsing.parse_kwargs("log=\"log\" ") == Dict(:log => "log")
    end

    @testset "Arrays, Tuples and Ranges" begin
        # Arrays
        @test Parsing.parse_kwargs("levels=[1, 2, 4]") == Dict(:levels => [1, 2, 4])
        @test Parsing.parse_kwargs("levels=[1, 2, 4]")[:levels] isa Vector{Int}
        @test Parsing.parse_kwargs("levels=[1.0, 2.5, 3.75]")[:levels] isa Vector{Float64}
        @test Parsing.parse_kwargs("colors=[\"red\", \"green\", \"blue\"]") == Dict(:colors => ["red", "green", "blue"])
        @test Parsing.parse_kwargs("mixed=[1, :a, \"text\"]") == Dict(:mixed => [1, :a, "text"])
        @test Parsing.parse_kwargs("mixed=[1, :a, \"text\"]")[:mixed][1] isa Int
        @test Parsing.parse_kwargs("spaces=[1.0, 2.5,3.75 ]") == Dict(:spaces => [1.0, 2.5, 3.75])
        @test Parsing.parse_kwargs("empty_array=[]") == Dict(:empty_array => [])

        # Tuples
        @test Parsing.parse_kwargs("colorrange=(0, 1)") == Dict(:colorrange => (0, 1))
        @test Parsing.parse_kwargs("range=(-1.0,1.0)") == Dict(:range => (-1.0, 1.0))
        @test Parsing.parse_kwargs("mixed_tuple=(2e-3, :b, \"label\")") == Dict(:mixed_tuple => (2e-3, :b, "label"))

        # Ranges
        @test Parsing.parse_kwargs("data=1:10") == Dict(:data => 1:10)
        @test Parsing.parse_kwargs("data=1:2:10") == Dict(:data => 1:2:10)
        @test Parsing.parse_kwargs("data=-1:10") == Dict(:data => -1:10)
        @test Parsing.parse_kwargs("data=4:-2:10") == Dict(:data => 4:-2:10)
        @test Parsing.parse_kwargs("data=-0.1:0.1:1.0") == Dict(:data => -0.1:0.1:1.0)
        @test Parsing.parse_kwargs("data=1:0.2:10") == Dict(:data => 1:0.2:10)

    end

    @testset "Expressions" begin
        # the reported case: a module-qualified call has to come back as the
        # object it names, not as the string it was typed as
        scale = Parsing.parse_kwargs("colorscale=Makie.Symlog10(1e-2)")[:colorscale]
        @test !(scale isa AbstractString)
        @test scale isa Makie.ReversibleScale  # what Makie.Symlog10 builds
        @test scale.name === :Symlog10
        @test scale(1.0) == Makie.Symlog10(1e-2)(1.0)

        # calls, qualified names, and constructors from the modules a plot
        # attribute usually reaches for
        @test Parsing.parse_kwargs("color=RGBf(1, 0, 0)") == Dict(:color => RGBf(1, 0, 0))
        @test Parsing.parse_kwargs("colormap=Makie.automatic")[:colormap] === Makie.automatic
        @test Parsing.parse_kwargs("offset=Point2f(0, 0)") == Dict(:offset => Point2f(0, 0))
        @test Parsing.parse_kwargs("color=HSV(120, 1, 1)") == Dict(:color => Colors.HSV(120, 1, 1))
        @test Parsing.parse_kwargs("step=Dates.Day(1)") == Dict(:step => Dates.Day(1))
        @test Parsing.parse_kwargs("linewidth=1 + 2") == Dict(:linewidth => 3)

        # a colon is not enough to make a range -- these used to stop at the
        # range branch and come back as strings
        @test Parsing.parse_kwargs("lookup=Dict(:a => 1)") == Dict(:lookup => Dict(:a => 1))
        @test Parsing.parse_kwargs("size=map(x -> 2x, 1:3)") == Dict(:size => [2, 4, 6])

        # bare words are words, not names to look up
        @test Parsing.parse_kwargs("title=Foo") == Dict(:title => "Foo")
        @test Parsing.parse_kwargs("filename=output") == Dict(:filename => "output")
        @test Parsing.parse_kwargs("levels=not_a_number") == Dict(:levels => "not_a_number")
        @test Parsing.parse_kwargs("title=Foo")[:title] isa AbstractString

        # and neither is a file name, even though it parses as an expression
        @test Parsing.parse_kwargs("filename=output.png") == Dict(:filename => "output.png")
        @test Parsing.parse_kwargs("filename=my_movie.mp4") == Dict(:filename => "my_movie.mp4")
        @test Parsing.parse_kwargs("filename=out/plot.png") == Dict(:filename => "out/plot.png")
        # a file name is a silent fallback: every save options line would
        # spew errors otherwise
        @test_logs Parsing.parse_kwargs("filename=output.png")

        # a call that does not evaluate is named out loud, and still falls
        # back to the string
        typo = @test_logs (:error,) Parsing.parse_kwargs("colorscale=Makie.Symlog11(1e-2)")
        @test typo == Dict(:colorscale => "Makie.Symlog11(1e-2)")

        # the sandbox is its own module: Base is reachable, the caller is not
        @test Parsing.parse_kwargs("value=identity(1)") == Dict(:value => 1)
        @test (@test_logs (:error,) Parsing.parse_kwargs("value=parsing_test_probe(1)")) ==
              Dict(:value => "parsing_test_probe(1)")
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

    @testset "Naming Without Reading" begin
        # what a line names, split the same way but left as text
        @test Parsing.kwarg_entries("colormap=:viridis, linewidth=2") ==
              ["colormap" => ":viridis", "linewidth" => "2"]
        @test Parsing.kwarg_entries("theme=\"dark\"") == ["theme" => "\"dark\""]
        @test Parsing.kwarg_entries("") == Pair{String, String}[]

        # a comma inside quotes or brackets still does not start a new entry
        @test Parsing.kwarg_entries("""xlabel = "Time, (s)", levels=[1, 2]""") ==
              ["xlabel" => "\"Time, (s)\"", "levels" => "[1, 2]"]

        # a word that is not a pair is not one
        @test Parsing.kwarg_entries("theme dark") == Pair{String, String}[]

        # nothing is evaluated, so a value that would be reported is not
        @test (@test_logs Parsing.kwarg_entries("value=parsing_test_probe(1)")) ==
              ["value" => "parsing_test_probe(1)"]
    end
end