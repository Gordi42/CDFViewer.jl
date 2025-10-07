module ViewerREPL

import REPL
using REPL.TerminalMenus
using Term
using DataStructures
using GLMakie

using CDFViewer.Controller
using CDFViewer.Data
using CDFViewer.Parsing
using CDFViewer.Plotting


struct REPLState
    controller:: Controller.ViewerController
    history:: Vector{String}

    function REPLState(controller:: Controller.ViewerController)
        new(controller, String[])
    end
end

# ============================================================ 
#  REPL Commands
# ============================================================ 

struct REPLCommand
    name:: String
    description:: String
    usage:: String
    action:: Function
end

commands = OrderedDict{String, REPLCommand}()

# ============================================================ 
#  Helpers
# ============================================================ 
function get_from_menu(options:: Vector{String}, prompt:: String):: String
    menu = RadioMenu(options, pagesize=6)
    choice = request(prompt, menu)
    if choice != -1
        options[choice]
    else
        ""
    end
end

function select_menu_option!(menu:: Menu, command:: String)::String
    parts = split(command, ' ', limit=2)
    avail_opt = menu.options[]
    if length(parts) < 2
        selection = get_from_menu(avail_opt, "Select:")
        if isempty(selection)
            return "Nothing selected."
        end
    else
        selection = parts[2]
    end

    if !(selection in avail_opt)
        @warn "Invalid selection: $selection"
        return "Available options: \n" * join(avail_opt, ", ")
    end
    menu.i_selected[] = findfirst(==(selection), menu.options[])
    "Selected: $selection"
end

# ============================================================ 
#  Command Implementations
# ============================================================ 
function select_variable(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.variable_menu
    select_menu_option!(menu, command)
end

function select_plot_type(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.plot_menu.plot_type
    select_menu_option!(menu, command)
end

function select_x_axis(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.coord_menu.menus[1]
    select_menu_option!(menu, command)
end

function select_y_axis(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.coord_menu.menus[2]
    select_menu_option!(menu, command)
end

function select_z_axis(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.coord_menu.menus[3]
    select_menu_option!(menu, command)
end

function select_index(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=3)
    if length(parts) < 3
        @warn "Usage: isel <dimension> <index>"
        return ""
    end
    cmd, dim, idx_str = parts
    idx = try
        parse(Int, idx_str)
    catch
        @warn "Index must be an integer."
        return ""
    end
    sliders = state.controller.ui.main_menu.coord_sliders.sliders
    if !haskey(sliders, dim)
        @warn "Dimension '$dim' not found."
        return ""
    end
    slider = sliders[dim]
    slider_range = slider.range[]
    if idx < minimum(slider_range) || idx > maximum(slider_range)
        @warn "Index out of range for dimension '$dim'. Valid range: $(slider_range)"
        return ""
    end
    set_close_to!(slider, idx)
    # Print the current value label for the dimension
    dataset = state.controller.dataset
    Data.get_dim_value_label(dataset, String(dim), idx)
end

function select_value(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=3)
    if length(parts) < 3
        @warn "Usage: sel <dimension> <index>"
        return ""
    end
    cmd, dim, val_str = parts
    val = try
        parse(Float64, val_str)
    catch
        @warn "Value must be a number."
        return ""
    end
    sliders = state.controller.ui.main_menu.coord_sliders.sliders
    if !haskey(sliders, dim)
        @warn "Dimension '$dim' not found."
        return ""
    end
    slider = sliders[dim]

    # Find the closest index to the specified value
    dataset = state.controller.dataset
    dim_values = getproperty(dataset.interp.rc, Symbol(dim))
    idx = argmin(abs.(dim_values .- val))

    set_close_to!(slider, idx)
    # Print the current value label for the dimension
    Data.get_dim_value_label(dataset, String(dim), idx)
end

function toggle_play(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    if length(parts) > 1
        set_play_dimension(state, command)
    end
    toggle = state.controller.ui.main_menu.playback_menu.toggle
    toggle.active[] = !toggle.active[]
    toggle.active[] ? "Playing." : "Paused."
end

function set_play_speed(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    speed_slider = state.controller.ui.main_menu.playback_menu.speed
    if length(parts) < 2
        return "Current speed: $(10.0 ^ speed_slider.value[])"
    end
    cmd, speed_str = parts
    speed = try
        parse(Float64, speed_str)
    catch
        @warn "Speed must be a number."
        return ""
    end
    # The speed slider range is in log10 space
    adjusted_value = log10(speed)
    set_close_to!(speed_slider, adjusted_value)
    "New speed: $(10.0 ^ speed_slider.value[])"
end

function set_play_dimension(state:: REPLState, command:: String)::String
    menu = state.controller.ui.main_menu.playback_menu.var
    select_menu_option!(menu, command)
end

function save_figure(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    if length(parts) > 1
        additional_kwargs = parts[2]
    else
        additional_kwargs = ""
    end
    export_options = state.controller.ui.main_menu.export_menu.options
    if !isempty(additional_kwargs)
        try
            export_options.displayed_string = additional_kwargs
            export_options.stored_string = additional_kwargs
        catch e
            @warn "Error parsing additional arguments: $e"
            return ""
        end
    end
    notify(state.controller.ui.main_menu.export_menu.save_button.clicks)
    ""
end

function record_movie(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    if length(parts) > 1
        additional_kwargs = parts[2]
    else
        additional_kwargs = ""
    end
    export_options = state.controller.ui.main_menu.export_menu.options
    if !isempty(additional_kwargs)
        try
            export_options.displayed_string = additional_kwargs
            export_options.stored_string = additional_kwargs
        catch e
            @warn "Error parsing additional arguments: $e"
            return ""
        end
    end
    [wait(t) for t in state.controller.fd.tasks[]]
    notify(state.controller.ui.main_menu.export_menu.record_button.clicks)
    ""
end

function export_string(state:: REPLState, command:: String)::String
    notify(state.controller.ui.main_menu.export_menu.export_button.clicks)
    ""
end

function show_figure(state:: REPLState, command:: String)::String
    Controller.open_window!(
        state.controller,
        state.controller.fig_screen,
        state.controller.fd.fig,
        "CDFViewer - Figure",
    )
    "Opened figure window."
end

function hide_figure(state:: REPLState, command:: String)::String
    Controller.hide_window!(
        state.controller,
        state.controller.fig_screen,
    )
    "Closed figure window."
end

function show_menu(state:: REPLState, command:: String)::String
    Controller.open_window!(
        state.controller,
        state.controller.menu_screen,
        state.controller.ui.menu,
        "CDFViewer - Menu",
    )
    "Opened menu window."
end

function hide_menu(state:: REPLState, command:: String)::String
    Controller.hide_window!(
        state.controller,
        state.controller.menu_screen,
    )
    "Closed menu window."
end

function get_figure_kwargs(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    @bold("Figure keywords:\n  ") * join(propertynames(fd.settings), "\n  ")
end

function get_axis_kwargs(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    @bold("Axis keywords:\n  ") * join(propertynames(fd.ax[]), "\n  ")
end

function get_plot_kwargs(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    @bold("Plot keywords:\n  ") * join(propertynames(fd.plot_obj[]), "\n  ")
end

function get_colorbar_kwargs(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    @bold("Colorbar keywords:\n  ") * join(propertynames(fd.cbar[]), "\n  ")
end

function get_range_kwargs(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    @bold("Range keywords:\n  ") * join(propertynames(fd.range_control[]), "\n  ")
end

function get_kwargs_list(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    if length(parts) > 1
        category = lowercase(parts[2])
        if category == "figure"
            return get_figure_kwargs(state, command)
        elseif category == "axis"
            return get_axis_kwargs(state, command)
        elseif category == "plot"
            return get_plot_kwargs(state, command)
        elseif category == "colorbar"
            return get_colorbar_kwargs(state, command)
        elseif category == "range"
            return get_range_kwargs(state, command)
        else
            @warn "Unknown category: $category. Valid categories are: figure, axis, plot, colorbar, range."
            return ""
        end
    end

    fd = state.controller.fd
    output = "Available keyword arguments:\n"
    output *= get_figure_kwargs(state, command)
    if !isnothing(fd.ax[])
        output *= "\n" * get_axis_kwargs(state, command)
    end
    if !isnothing(fd.plot_obj[])
        output *= "\n" * get_plot_kwargs(state, command)
    end
    if !isnothing(fd.cbar[])
        output *= "\n" * get_colorbar_kwargs(state, command)
    end
    output *= "\n" * get_range_kwargs(state, command)
    output
end

function get_kwarg_value(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    if length(parts) < 2
        @warn "Usage: get <key>"
        return ""
    end
    key = parts[2]
    fd = state.controller.fd
    kwargs = OrderedDict{Symbol, Any}()
    kwargs[Symbol(key)] = nothing
    mappings = Plotting.get_property_mappings(kwargs, fd)
    if isempty(mappings)
        return ""
    end
    value = mappings[1].current_value
    try
        value = value[] # try to dereference if it's an Observable
    catch
        # do nothing
    end
    if isa(value, AbstractString)
        "$key => \"$value\""
    elseif isa(value, Symbol)
        "$key => :$value"
    else
        "$key => $value"
    end
end

function refresh_plot(state:: REPLState, command:: String)::String
    fd = state.controller.fd
    Plotting.clear_axis!(fd)
    Plotting.create_axis!(fd, state.controller.ui.state)
    "Plot refreshed."
end

function update_kwargs(state:: REPLState, new_kwargs::OrderedDict{Symbol, Any})::Nothing
    textbox = state.controller.ui.main_menu.plot_menu.plot_kw
    new_kw_string = Plotting.kwarg_dict_to_string(new_kwargs)
    new_display_string = isempty(new_kw_string) ? " " : new_kw_string
    try
        textbox.displayed_string = new_display_string
        textbox.stored_string = new_kw_string
    catch e
        @warn "Error parsing additional arguments: $e"
    end
    nothing
end

function apply_kwargs(state:: REPLState, command:: String)::String
    # Get the current additional arguments string
    current_kwargs = state.controller.ui.state.kwargs[]
    new_kwargs = Parsing.parse_kwargs(command)
    merged_kwargs = merge(current_kwargs, new_kwargs)
    update_kwargs(state, merged_kwargs)
    get_plot_settings(state, "")
end

function delete_kwarg(state:: REPLState, command:: String)::String
    parts = split(command, ' ')
    if length(parts) < 2
        @warn "Usage: del <key>"
        return ""
    end
    kwargs = copy(state.controller.ui.state.kwargs[])
    for key in parts[2:end]
        if !haskey(kwargs, Symbol(key))
            @warn "Key '$key' not found in current kwargs."
            continue
        end
        delete!(kwargs, Symbol(key))
    end
    update_kwargs(state, kwargs)
    get_plot_settings(state, "")
end

function get_variable_list(state:: REPLState, command:: String)::String
    var_options = state.controller.ui.main_menu.variable_menu.options[]
    "Available variables: \n" * join(var_options, ", ")
end

function get_plot_types(state:: REPLState, command:: String)::String
    plot_types = state.controller.ui.main_menu.plot_menu.plot_type.options[]
    "Available plot types: \n" * join(plot_types, ", ")
end

function get_var_info(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    var_name = if length(parts) == 1
        # get the currently selected variable
        menu = state.controller.ui.main_menu.variable_menu
        menu.selection[]
    else
        parts[2]
    end
    if !haskey(state.controller.dataset.var_coords, var_name)
        @warn "Variable '$var_name' not found."
        return ""
    end
    string(state.controller.dataset.ds[var_name])
end

function get_dim_list(state:: REPLState, command:: String)::String
    parts = split(command, ' ', limit=2)
    var_name = if length(parts) == 1
        # get the currently selected variable
        menu = state.controller.ui.main_menu.variable_menu
        menu.selection[]
    else
        parts[2]
    end
    # Get the coordinates of this variable
    if !haskey(state.controller.dataset.var_coords, var_name)
        @warn "Variable '$var_name' not found."
        return ""
    end
    var_coords = state.controller.dataset.var_coords[var_name]

    sliders = state.controller.ui.main_menu.coord_sliders.sliders
    dataset = state.controller.dataset
    output = "List of Dimensions: \n"
    for coord in var_coords
        slider = sliders[coord]
        output *= Data.get_dim_value_label(dataset, coord, slider.value[]) * "\n"
    end
    output
end

function get_plot_settings(state:: REPLState, command:: String)::String
    current_kwargs = state.controller.ui.state.kwargs[]
    entries = String[]
    for (k,v) in current_kwargs
        if isa(v, AbstractString)
            push!(entries, "$k => \"$v\"")
        elseif isa(v, Symbol)
            push!(entries, "$k => :$v")
        else
            push!(entries, "$k => $v")
        end
    end
    "Current plot settings:\n" * join(entries, "\n")
end

function reset_plot_settings(state:: REPLState, command:: String)::String
    new_kwargs = OrderedDict{Symbol, Any}()
    update_kwargs(state, new_kwargs)
    refresh_plot(state, "")
    "Reset plot settings to default."
end

function get_help(state:: REPLState, command:: String)::String
    # Print all commands and their descriptions from the commands dictionary
    output = "Type 'exit' or 'quit' to leave the REPL.\n"
    output *= "Available commands:\n"
    for cmd_struct in values(commands)
        output *= "  " * @bold(cmd_struct.name) * ": " * cmd_struct.description * " (" * cmd_struct.usage * ")\n"
    end
    output *= "You can also set parameters directly using '" * @bold("key=value") * "' syntax.\n"
    output *= "For a list of available keyword arguments, type '" * @bold("kwargs") * "'."
    output
end

# ============================================================ 
#  Populate Commands Dictionary
# ============================================================ 

function register_command(cmd:: REPLCommand)
    commands[cmd.name] = cmd
end

function __init_commands!()
    r = (cmd) -> register_command(cmd)
    # Populate the commands dictionary after all functions are defined
    r(REPLCommand("v", "Select a variable", "v [variable_name]", select_variable))
    r(REPLCommand("p", "Select a plot type", "p [plot_type]", select_plot_type))
    r(REPLCommand("x", "Select x-axis variable", "x [variable_name]", select_x_axis))
    r(REPLCommand("y", "Select y-axis variable", "y [variable_name]", select_y_axis))
    r(REPLCommand("z", "Select z-axis variable", "z [variable_name]", select_z_axis))
    r(REPLCommand("isel", "Select index for a dimension", "isel <dim_name> <index>", select_index))
    r(REPLCommand("sel", "Select value for a dimension", "sel <dim_name> <value>", select_value))
    r(REPLCommand("play", "Toggle play/pause for animations", "play [dim_name]", toggle_play))
    r(REPLCommand("speed", "Set play speed", "speed [value]", set_play_speed))
    r(REPLCommand("pdim", "Set play dimension", "pdim [dim_name]", set_play_dimension))
    r(REPLCommand("savefig", "Save the current figure",
        "savefig [filename=<filename>, px_per_unit=<Int>]", save_figure))
    r(REPLCommand("record", "Record a movie",
        "record [filename=<filename>, framerate=<Int>, range=<range>]", record_movie))
    r(REPLCommand("export", "Export the current figure as a string", "export", export_string))
    r(REPLCommand("show", "Show the current figure", "show", show_figure))
    r(REPLCommand("hide", "Hide the current figure", "hide", hide_figure))
    r(REPLCommand("menu", "Show the menu", "menu", show_menu))
    r(REPLCommand("hidemenu", "Hide the menu", "hidemenu", hide_menu))
    r(REPLCommand("refresh", "Refresh the plot", "refresh", refresh_plot))
    r(REPLCommand("reset", "Reset plot settings to default", "reset", reset_plot_settings))
    r(REPLCommand("help", "Get help", "help", get_help))
    r(REPLCommand("kwargs", "Get a list of available keyword arguments", "kwargs [category]" , get_kwargs_list))
    r(REPLCommand("get", "Get the value of a keyword argument", "get <kwarg_name>", get_kwarg_value))
    r(REPLCommand("vars", "Get a list of variables", "vars", get_variable_list))
    r(REPLCommand("varinfo", "Get information about a variable", "varinfo [variable_name]", get_var_info))
    r(REPLCommand("dims", "Get a list of dimensions", "dims", get_dim_list))
    r(REPLCommand("plots", "Get a list of plot types", "plots", get_plot_types))
    r(REPLCommand("conf", "Get the current plot configuration", "conf", get_plot_settings))
    r(REPLCommand("del", "Delete a keyword argument", "del <kwarg_name>", delete_kwarg))
end

__init_commands!()


function evaluate_command(state:: REPLState, command_line:: String)::Union{String, Bool}
    command_parts = split(command_line)
    if isempty(command_parts)
        return ""
    end
    cmd = command_parts[1]
    if cmd == "exit" || cmd == "quit" || cmd == "q"
        return false
    elseif haskey(commands, cmd)
        try
            return commands[cmd].action(state, command_line)
        catch e
            @error "Error executing command '$cmd': $e"
            return ""
        end
    elseif occursin('=', command_line)
        try
            return apply_kwargs(state, command_line)
        catch e
            @error "Error executing command '$cmd': $e"
            return ""
        end
    else
        @warn "Unknown command: $cmd. Type 'help' for a list of commands."
        return ""
    end
end

# ============================================================ 
#  REPL Loop
# ============================================================ 

function start_repl(controller:: Controller.ViewerController)::Nothing
    state = REPLState(controller)
    println("Type 'help' for a list of commands.")
    running = true

    while running
        try
            print("CDFViewer> ")

            if eof(stdin)
                @info "Exiting CDFViewer REPL."
                running = false
                break
            end

            command_line = String(strip(readline()))
            push!(state.history, command_line)
            status = evaluate_command(state, command_line)
            if isa(status, Bool) && status == false
                running = false
                break
            end
            !isempty(status) && @info status
        catch e
            if isa(e, InterruptException)
                @warn "Interrupted. Type 'exit', 'quit', or 'q' to leave the REPL."
                continue
            end
            @info "Exiting CDFViewer REPL."
            running = false
            break
        end
    end
    nothing
end

end