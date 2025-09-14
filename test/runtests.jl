using Test
using CDFViewer

results = @testset "CDFViewer Tests" begin
    include("test_setup.jl")
    include("test_interpolate.jl")
    include("test_data.jl")
    include("test_output.jl")
    include("test_ui.jl")
    include("test_parsing.jl")
    include("test_plotting.jl")
    include("test_controller.jl")
    include("test_argparse.jl")
    include("test_julia_main.jl")
end