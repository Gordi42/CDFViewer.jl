module CDFViewer

using ArgParse
using GLMakie

include("Constants.jl")
include("Parsing.jl")
include("Data.jl")
include("UI.jl")
include("Plotting.jl")
include("Output.jl")
include("Controller.jl")

export julia_main

function get_arg_parser()::ArgParseSettings
    s = ArgParseSettings()

    @add_arg_table! s begin
        "files"
            help = "Path(s) to the NetCDF file(s) to open"
            arg_type = String
            nargs = '+'  # one or more files
            required = true
        # Options
        "--var", "-v"
            help = "Variable to plot"
            arg_type = String
            default = ""
        "--x-axis", "-x"
            help = "X-axis variable"
            arg_type = String
            default = ""
        "--y-axis", "-y"
            help = "Y-axis variable"
            arg_type = String
            default = ""
        "--z-axis", "-z"
            help = "Z-axis variable (for 3D plots)"
            arg_type = String
            default = ""
        "--plot_type", "-p"
            help = "Type of plot to generate (e.g., contour, surface, scatter)"
            arg_type = String
            default = ""
        "--kwargs"
            help = "Additional keyword arguments for the plot (as a Julia expression)"
            arg_type = String
            default = ""
        "--dims"
            help = "Dimensions indices as key=index pairs, e.g., '--dims=time=5,lat=10'"
            arg_type = String
            default = ""
        "--ani-dim", "-a"
            help = "Dimension to use for animation"
            arg_type = String
            default = ""
        "--saveoptions", "-s"
            help = "Options for saving the figure (as a Julia expression)"
            arg_type = String
            default = ""
        # Flags
        "--savefig"
            help = "Only save the figure to file and exit"
            action = :store_true
        "--record"
            help = "Only record the animation to a video file and exit"
            action = :store_true
        "--no-menu"
            help = "Disable the menu and only show the plot"
            action = :store_true
        "--use-local"
            help = "Use local directory for temporary operations to improve performance. Set CDFVIEWER_USE_LOCAL=true to make it default. The local directory can be changed with the environment variable CDFVIEWER_LOCAL_DIR."
            action = :store_true
    end

    return s
end

function is_headless(testing::Bool, savefig::Bool, record::Bool)::Bool
    any([testing, savefig, record])
end

function julia_main(;parsed_args::Union{Nothing,Dict}=nothing)
    println("Running CDFViewer: $(Constants.APP_VERSION)")

    # whether to show the UI or not
    testing = !isnothing(parsed_args)  # if parsed_args are provided, we are testing

    # only parse command line if no args are provided (e.g. from tests)
    if isnothing(parsed_args)
        parsed_args = parse_args(get_arg_parser())
    end
    file_paths = parsed_args["files"]

    println("Loading dataset from file(s): $file_paths")
    dataset = Data.CDFDataset(file_paths)

    headless = is_headless(testing, parsed_args["savefig"], parsed_args["record"]) 

    println("Setup...")
    @time controller = Controller.ViewerController(
        dataset, headless=headless, parsed_args=parsed_args)
    println("Ready.")

    # Check if we need to save or record and exit
    parsed_args["savefig"] && notify(controller.ui.main_menu.export_menu.save_button.clicks)
    parsed_args["record"] && notify(controller.ui.main_menu.export_menu.record_button.clicks)

    if !headless
        main_screen = parsed_args["no-menu"] ? controller.fig_screen[] : controller.menu_screen[]
        wait(main_screen)
    end

    return 0
end

end # module CDFViewer
