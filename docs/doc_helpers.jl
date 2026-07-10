# Helper module for the documentation's `@example` blocks. It drives the
# application through the same entry points the interactive session uses
# (`Data.CDFDataset`, `ViewerController`, `evaluate_command`), so every
# transcript and screenshot in the manual is produced by the real code at
# build time and cannot go stale.

module DocHelpers

using Logging: ConsoleLogger, NullLogger, with_logger
using GLMakie
using CDFViewer
using CDFViewer: ArgParse, Controller, Data, ViewerREPL, get_arg_parser

export open_viewer, repl, run!, print_overview, menu_figure, plot_figure,
    close_viewer!, demo_file, publish_asset

# Set by make.jl to the directory holding the generated demo datasets
const DEMO_DIR = Ref("")

demo_file(name::String) = joinpath(DEMO_DIR[], name)

struct ViewerSession
    dataset::Data.CDFDataset
    controller::Controller.ViewerController
    state::ViewerREPL.REPLState
end

"""
Open the given files exactly like `julia_main` does (including the automatic
grid-file search), but headless and without starting the interactive prompt.
Extra command line arguments can be passed via `cli`.
"""
function open_viewer(files::String...; cli::String = "")::ViewerSession
    argv = vcat(collect(String, files), Base.shell_split(cli))
    args = ArgParse.parse_args(argv, get_arg_parser())
    # Suppress setup log messages (they would show build-machine temp paths)
    with_logger(NullLogger()) do
        dataset = Data.CDFDataset(
            args["files"],
            grid_file = args["grid"],
            grid_search = !args["no-grid-search"],
        )
        controller = Controller.ViewerController(
            dataset, headless = true, parsed_args = args, work_dir = pwd())
        ViewerSession(dataset, controller, ViewerREPL.REPLState(controller))
    end
end

wait_tasks(session::ViewerSession) =
    foreach(wait, session.controller.fd.tasks[])

"""
Run commands through the REPL evaluator and print prompt, command, and result
just like the interactive session does. Progress-bar frames (ProgressMeter
writes one per update to stderr, ~70 of them on a slow machine) are dropped
from the transcript.
"""
function repl(session::ViewerSession, commands::String...)::Nothing
    with_logger(ConsoleLogger(stdout)) do
        for cmd in commands
            printstyled("CDFViewer> ", color = :cyan, bold = true)
            println(cmd)
            pipe = Pipe()
            status = redirect_stderr(pipe) do
                s = ViewerREPL.evaluate_command(session.state, cmd)
                wait_tasks(session)
                s
            end
            close(pipe.in)
            for line in split(read(pipe, String), r"[\r\n]+")
                isempty(strip(line)) && continue
                occursin(r"Recording\s+\d+%", line) && continue
                println(line)
            end
            status isa String && !isempty(status) && @info status
        end
    end
    nothing
end

"""
Copy a file generated next to the page (the `@example` working directory)
into the page's pretty-URL directory as well. With `prettyurls = true` (CI),
`usage/foo.md` becomes `usage/foo/index.html`, so a relative `src="file"`
resolves inside `usage/foo/` — while the `@example` block wrote the file to
`usage/`. Publishing to both locations makes the same relative link work in
both URL modes.
"""
function publish_asset(file::String, page::String)::Nothing
    dir = joinpath(pwd(), page)
    mkpath(dir)
    cp(file, joinpath(dir, basename(file)), force = true)
    nothing
end

"""
Run commands without echoing a transcript (for page setup that should not
appear in the rendered output).
"""
function run!(session::ViewerSession, commands::String...)::Nothing
    with_logger(NullLogger()) do
        for cmd in commands
            ViewerREPL.evaluate_command(session.state, cmd)
            wait_tasks(session)
        end
    end
    nothing
end

"""
Print the dataset overview exactly as it appears when a file is opened.
"""
print_overview(session::ViewerSession) =
    print(stdout, Data.overview_string(session.dataset), "\n")

"""The menu window's figure (for screenshots)."""
menu_figure(session::ViewerSession) = session.controller.ui.menu

"""The plot window's figure (for screenshots)."""
function plot_figure(session::ViewerSession)
    wait_tasks(session)
    session.controller.fd.fig
end

function close_viewer!(session::ViewerSession)::Nothing
    GLMakie.closeall()
    close(session.dataset.ds)
    nothing
end

end # module DocHelpers
