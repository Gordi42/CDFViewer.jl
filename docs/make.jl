using Documenter
using CDFViewer
using GLMakie

# Deterministic rendering: ignore HiDPI scaling of the build machine
GLMakie.activate!(scalefactor = 1.0)

# Isolate the build from any user configuration on the build machine
ENV["CDFVIEWER_CONFIG"] = joinpath(mktempdir(), "config.toml")
ENV["CDFVIEWER_HISTORY"] = tempname()

include("demo_data.jl")
include("doc_helpers.jl")

demo_dir = mktempdir()
create_demo_file(demo_dir)
create_wave_file(demo_dir)
create_icon_demo(demo_dir)
DocHelpers.DEMO_DIR[] = demo_dir

makedocs(
    sitename = "CDFViewer.jl",
    authors = "Silvano Rosenau",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://gordi42.github.io/CDFViewer.jl",
        edit_link = "master",
    ),
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Usage" => [
            "Getting Started" => "usage/getting_started.md",
            "The Command REPL" => "usage/repl.md",
            "The Menu Window" => "usage/menu.md",
            "Selecting Data" => "usage/selecting_data.md",
            "Plot Types" => "usage/plot_types.md",
            "Customizing Plots" => "usage/customization.md",
            "Animation and Playback" => "usage/animation.md",
            "Saving and Recording" => "usage/saving.md",
            "Unstructured Grids" => "usage/unstructured.md",
            "Configuration" => "usage/configuration.md",
        ],
        "Reference" => [
            "Command Line Options" => "reference/cli.md",
            "REPL Commands" => "reference/commands.md",
        ],
    ],
)

deploydocs(
    repo = "github.com/Gordi42/CDFViewer.jl.git",
    devbranch = "master",
    versions = nothing,
)
