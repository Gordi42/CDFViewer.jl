module Controller

using Colors
using Printf
using Logging
using GLMakie
using DataStructures
using CDFViewer.Constants
using CDFViewer.Themes
using CDFViewer.Data
using CDFViewer.Output
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Parsing

# The UI and the figure are replaced whole when the theme changes -- a
# figure snapshots the theme at creation, so a new look means new windows.
# Everything that outlives such a rebuild (the dataset, the screens, the
# argument dict) stays put, which is what lets every reference to the
# controller -- the REPL's above all -- keep pointing at the live session.
mutable struct ViewerController
    ui::UI.UIElements
    fd::Plotting.FigureData
    const dataset::Data.CDFDataset
    watch_dim::Observable{Bool}
    watch_plot::Observable{Bool}
    # a theme switch takes both windows down and puts them back up with
    # the rebuilt figures in them. That is the app closing a window, not
    # the user, and it must not deselect the plot type on the way through
    watch_window::Observable{Bool}
    menu_screen::Observable{GLMakie.Screen}
    fig_screen::Observable{GLMakie.Screen}
    headless::Observable{Bool}
    parsed_args::Union{Nothing,Dict}
end

"""
    requested_theme(parsed_args)

The theme a command line asks for, refused by name when it names none.

The refusal happens here, at the edge, and not somewhere down in
`apply_kwargs!`: a message written to stderr in there is read as a failed
keyword and takes the whole batch down with it.
"""
function requested_theme(parsed_args::Union{Nothing,Dict})::String
    name = isnothing(parsed_args) ? "" : get(parsed_args, "theme", "")
    isempty(name) && return Themes.DEFAULT_THEME
    resolved = Themes.resolve(name)
    if isnothing(resolved)
        @warn Themes.unknown_theme_message(name)
        return Themes.DEFAULT_THEME
    end
    resolved
end

"""
    build_session!(controller)

Build the menu, the plot data and the figure under the theme that is
installed, and hang them on the controller.

Called once when a session starts and again on every theme switch, which
is why it takes nothing from the command line: what a session holds is
put back by `restore_session!`.
"""
function build_session!(controller::ViewerController)::Nothing
    ui = UI.UIElements(controller.dataset)
    plot_data = Plotting.PlotData(ui.state, controller.dataset)
    controller.ui = ui
    controller.fd = Plotting.FigureData(plot_data, ui)
    nothing
end

function ViewerController(dataset::Data.CDFDataset;
    headless::Bool = true,
    parsed_args::Union{Nothing,Dict} = nothing,
    work_dir::String = pwd(),
)::ViewerController
    # the theme goes in first: both windows snapshot it as they are built
    Themes.activate!(requested_theme(parsed_args))
    # Set up the UI
    ui = UI.UIElements(dataset)
    # Set the working directory for output settings
    ui.state.output_settings[].work_dir = work_dir
    ui.state.output_settings[].filename = get_standard_filename(parsed_args)
    # Set up the plotting
    plot_data = Plotting.PlotData(ui.state, dataset)
    fig_data = Plotting.FigureData(plot_data, ui)
    menu_screen = GLMakie.Screen(visible = false, title = "CDFViewer - Menu") # Start hidden
    fig_screen = GLMakie.Screen(visible = false, title = "CDFViewer - Figure")  # Start hidden
    display(menu_screen, ui.menu)
    display(fig_screen, fig_data.fig)
    parsed_args = isnothing(parsed_args) ? Dict() : parsed_args

    controller = ViewerController(
        ui, fig_data, dataset,
        Observable(true), Observable(true), Observable(true),
        Observable(menu_screen), Observable(fig_screen), Observable(true),
        parsed_args
    )
    setup!(controller)
    # wait until the tasks are done
    [wait(t) for t in controller.fd.tasks[]]
    Plotting.wait_for_scans(controller.fd)
    controller.headless[] = headless
    controller
end

"""
    connect_ui!(controller)

Wire the controller to the widgets and the figure it holds right now.

Everything in here hangs off something a theme switch replaces, so it is
registered again on every rebuild. The handlers that hang off the
controller's own observables and off the windows are not: those outlive a
rebuild, and registering them twice would run them twice.
"""
function connect_ui!(controller::ViewerController)::Nothing
    # Helper to convert functions to event handlers
    conv = func -> (_ -> func(controller))

    # Connect UI changes to controller functions
    on(conv(on_variable_change), controller.ui.main_menu.variable_menu.selection)
    on(conv(on_plot_type_change), controller.ui.main_menu.plot_menu.plot_type.selection)
    for menu in controller.ui.main_menu.coord_menu.menus
        on(conv(on_dim_sel_change), menu.selection)
    end
    on(tick -> on_tick_event(controller, tick), controller.fd.fig.scene.events.tick)
    on(conv(on_save_event), controller.ui.main_menu.export_menu.save_button.clicks)
    on(conv(on_record_event), controller.ui.main_menu.export_menu.record_button.clicks)
    on(conv(on_export_event), controller.ui.main_menu.export_menu.export_button.clicks)
    on(conv(on_keyboard_event), controller.fd.fig.scene.events.keyboardbutton)
    nothing
end

function setup!(controller::ViewerController)::ViewerController
    # Helper to convert functions to event handlers
    conv = func -> (_ -> func(controller))

    connect_ui!(controller)

    watch_window_close!(controller, controller.fig_screen[])
    on(conv(on_headless_change), controller.headless)

    # This will set everything up for the initial variable
    notify(controller.ui.main_menu.variable_menu.selection)

    # Process command line arguments
    process_parsed_args!(controller)

    # return the controller
    controller
end

function process_parsed_args!(controller::ViewerController)::Nothing
    parsed_args = controller.parsed_args
    isnothing(parsed_args) && return nothing
    # Set the variable(s) if provided
    if haskey(parsed_args, "var") && parsed_args["var"] != ""
        select_variables!(controller, parsed_args["var"])
    end

    # Set the axes if provided
    axis_keys = ["x-axis", "y-axis", "z-axis"]
    axis_menus = [controller.ui.main_menu.coord_menu.menus[i] for i in 1:3]
    for (key, menu) in zip(axis_keys, axis_menus)
        if haskey(parsed_args, key) && parsed_args[key] != ""
            dim = parsed_args[key]
            if dim in menu.options[]
                menu.i_selected[] = findfirst(==(dim), menu.options[])
            else
                avail_dims = menu.options[][2:end]  # skip the NOT_SELECTED_LABEL
                @warn "Dimension '$dim' not found for axis '$key'. Available dimensions: $(avail_dims)"
            end
        end
    end

    # Set the plot type if provided
    if haskey(parsed_args, "plot_type") && parsed_args["plot_type"] != ""
        plot_type = parsed_args["plot_type"]
        plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
        if plot_type in plot_type_menu.options[]
            plot_type_menu.i_selected[] = findfirst(==(plot_type), plot_type_menu.options[])
        else
            avail_plots = plot_type_menu.options[][2:end]  # skip the NOT_SELECTED_LABEL
            @warn "Plot type '$plot_type' not available. Available plot types: $(avail_plots)"
        end
    end

    # Process dimension indices if provided
    if haskey(parsed_args, "dims") && parsed_args["dims"] != ""
        dim_str = parsed_args["dims"]
        dim_dict = Parsing.parse_kwargs(dim_str)
        for (dim, idx) in dim_dict
            dim = string(dim)  # Convert Symbol to String
            if dim ∈ keys(controller.ui.main_menu.coord_sliders.sliders)
                slider = controller.ui.main_menu.coord_sliders.sliders[dim]
                # check if idx is numeric
                if !isa(idx, Number)
                    @warn "Dimension index for '$dim' must be a number. Got: $idx"
                    continue
                end
                set_close_to!(slider, idx)
            else
                avail_dims = keys(controller.ui.main_menu.coord_sliders.sliders)
                @warn "Dimension '$dim' not found for sliders. Available dimensions: $(avail_dims)"
            end
        end
    end

    # Process animation dimension if provided
    if haskey(parsed_args, "ani-dim") && parsed_args["ani-dim"] != ""
        ani_dim = parsed_args["ani-dim"]
        playback_menu = controller.ui.main_menu.playback_menu.var
        if ani_dim in playback_menu.options[]
            playback_menu.i_selected[] = findfirst(==(ani_dim), playback_menu.options[])
        else
            avail_dims = playback_menu.options[][2:end]  # skip the NOT_SELECTED_LABEL
            @warn "Animation dimension '$ani_dim' not found. Available dimensions: $(avail_dims)"
        end
    end

    # Create the overlay layers -- before the keywords are written, or a
    # prefixed one would find no layer to address and warn about it
    select_overlays!(controller)

    # Process kwargs if provided
    if haskey(parsed_args, "kwargs") && parsed_args["kwargs"] != ""
        Plotting.update_kwargs!(
            controller.fd, Parsing.parse_kwargs(parsed_args["kwargs"]))
    end

    # Process saveoptions if provided
    if haskey(parsed_args, "saveoptions")
        UI.apply_output_settings!(controller.ui.state, parsed_args["saveoptions"])
    end

    nothing
end

# ------------------------------------------------
#  Switching the theme
# ------------------------------------------------
#
# A figure snapshots the global theme at creation and never looks at it
# again, so a new look means new figures -- both of them, the plot window
# and the menu window. Everything the session is made of is copied out
# first, as values, and put back afterwards.
#
# Copied out, not written out: `get_export_string` describes a session
# well enough to restart it, but only through text, and text cannot carry
# a keyword whose value is an object (`colorscale=Makie.Symlog10(1e-2)`).

"""
Everything a session is, taken as values so a rebuilt one can be put back
into it. `get_export_string` is the checklist this follows.
"""
struct SessionState
    variable::String
    variable2::String
    plot_type::String
    axes::NTuple{3, String}
    # (variables, plot type) of each overlaid layer, base excluded
    layers::Vector{Tuple{Vector{String}, String}}
    dims::Dict{String, Int}
    pdim::String
    speed::Float64
    playing::Bool
    live_slider_update::Bool
    kwargs::OrderedDict{Symbol, Any}
    output_settings::Output.OutputSettings
    figsize::Tuple{Int, Int}
    # the zoom, as the axis reports it, and the 3D camera angles; nothing
    # when the figure has no axis or the extent cannot be handed back
    limits::Union{Nothing, Tuple}
    view3d::Union{Nothing, Tuple{Float64, Float64}}
end

"The zoom of the current axis, or nothing when it cannot be replayed."
function captured_limits(controller::ViewerController)::Union{Nothing, Tuple}
    ax = controller.fd.ax[]
    isnothing(ax) && return nothing
    limits = Plotting.get_limit_string(ax)
    Plotting.replayable_limits(limits) ? limits : nothing
end

"Take a copy of everything the session holds."
function capture_session(controller::ViewerController)::SessionState
    state = controller.ui.state
    main_menu = controller.ui.main_menu
    fd = controller.fd
    # let the background scans land first: a pin arriving after the swap
    # would write into the figure that has just been thrown away
    [wait(t) for t in fd.tasks[]]
    Plotting.wait_for_scans(fd)
    layers = [(Plotting.layer_variables(fd, i), Plotting.layer_plot(fd, i).type)
              for i in 2:Plotting.layer_count(fd)]
    ax = fd.ax[]
    figwidths = fd.fig.scene.viewport[].widths
    SessionState(
        state.variable[],
        state.variable2[],
        state.plot_type_name[],
        (state.x_name[], state.y_name[], state.z_name[]),
        layers,
        copy(state.dim_obs[]),
        state.pdim[],
        Float64(main_menu.playback_menu.speed.value[]),
        main_menu.playback_menu.toggle.active[],
        main_menu.coord_sliders.auto_update.active[],
        copy(state.kwargs[]),
        state.output_settings[],
        (Int(figwidths[1]), Int(figwidths[2])),
        captured_limits(controller),
        ax isa Axis3 ? (Float64(ax.azimuth[]), Float64(ax.elevation[])) : nothing,
    )
end

"Pick a named option when the menu still offers it."
function reselect!(menu::Menu, selection::AbstractString)::Nothing
    index = findfirst(==(selection), menu.options[])
    isnothing(index) || (menu.i_selected[] = index)
    nothing
end

"""
    restore_session!(controller, session)

Put a captured session back into a freshly built one.

The order is `process_parsed_args!`'s, because the same reconciliation
runs behind it: the variable rebuilds the plot type options, the plot
type rebuilds the second component, and the layers have to exist before
a keyword prefixed with one can find it.
"""
function restore_session!(controller::ViewerController,
                          session::SessionState)::Nothing
    main_menu = controller.ui.main_menu
    reselect!(main_menu.variable_menu, session.variable)
    for (menu, dim) in zip(main_menu.coord_menu.menus, session.axes)
        reselect!(menu, dim)
    end
    reselect!(main_menu.plot_menu.plot_type, session.plot_type)
    reselect!(main_menu.variable2_menu, session.variable2)
    for (dim, index) in session.dims
        slider = get(main_menu.coord_sliders.sliders, dim, nothing)
        isnothing(slider) && continue
        set_close_to!(slider, clamp(index, extrema(slider.range[])...))
    end
    reselect!(main_menu.playback_menu.var, session.pdim)
    set_close_to!(main_menu.playback_menu.speed, session.speed)
    main_menu.coord_sliders.auto_update.active[] = session.live_slider_update
    for (index, (names, plot_type)) in enumerate(session.layers)
        layer = index + 1
        isempty(set_layer_variables!(controller, layer, names)) && continue
        set_layer_plot_type!(controller, layer, plot_type)
    end
    controller.ui.state.output_settings[] = session.output_settings
    Plotting.update_kwargs!(controller.fd, session.kwargs)
    # the zoom and the figure size last, and outside the keyword store:
    # they are what is on screen, not what the user typed, and a theme
    # switch must not leave `conf` showing keywords nobody set. The zoom
    # goes in first and the resize after it, so the relayout the resize
    # sets off derives the view from the restored extent rather than
    # having to be told about it a second time
    restore_view!(controller, session)
    Plotting.resize_figure!(controller.fd, session.figsize)
    # playback goes back on once there is something to play
    main_menu.playback_menu.toggle.active[] = session.playing
    nothing
end

"Put the zoom and, on a 3D axis, the camera angles back."
function restore_view!(controller::ViewerController,
                       session::SessionState)::Nothing
    ax = controller.fd.ax[]
    isnothing(ax) && return nothing
    # written the way a keyword is written, through `setproperty!`: an
    # axis attribute is a node of a compute graph, and assigning into the
    # value it hands back moves the view without telling the graph --
    # the next `reset_limits!` (one runs on every save) undoes it again
    if !isnothing(session.view3d) && ax isa Axis3
        setproperty!(ax, :azimuth, session.view3d[1])
        setproperty!(ax, :elevation, session.view3d[2])
    end
    isnothing(session.limits) && return nothing
    # a rebuilt axis of another kind cannot take the old extent (a 2D
    # rectangle means nothing to an Axis3), so only replay a matching one
    length(session.limits) == (ax isa Axis3 ? 6 : 4) || return nothing
    try
        setproperty!(ax, :limits, session.limits)
    catch e
        @warn "Could not restore the axis limits: $e"
    end
    nothing
end

"""
    reattach_windows!(controller)

Put the rebuilt figures back on screen.

Each window is taken down and put up again rather than handed the new
figure directly. Re-displaying leaves the scenes of the old figure
registered with the screen, and a later frame is then drawn through one
of their cameras -- a zoomed map comes back showing the whole world.
GLMakie hands the same window straight back out of its reuse pool, so
the round trip is cheap and the window keeps its place.

Called while the figures are still empty, which is the order a session
starts in: a screen takes the plots that exist when it is handed the
figure, and a screen that has taken them will not let a second one --
the offscreen screen `savefig` renders through -- take them as well.
"""
function reattach_windows!(controller::ViewerController)::Nothing
    # closing a window here is the app's doing, not the user's
    controller.watch_window[] = false
    try
        # one at a time: GLMakie's pool of reusable windows is a set, and
        # two windows in it at once could come back the other way round
        swap_window!(controller, controller.menu_screen, controller.ui.menu,
                     "CDFViewer - Menu"; watch_close = false)
        swap_window!(controller, controller.fig_screen, controller.fd.fig,
                     "CDFViewer - Figure"; watch_close = true)
    finally
        controller.watch_window[] = true
    end
    nothing
end

"""
    swap_window!(controller, screen, fig, title; watch_close)

Take one window down and put it back up with `fig` in it.

A window the user has closed stays closed: `open_window!` builds a screen
for the new figure when it is asked for again. Only the figure window is
watched for closing -- that is what deselects the plot type, and the menu
window closing must not do it.
"""
function swap_window!(controller::ViewerController,
                      screen::Observable{GLMakie.Screen},
                      fig::Figure, title::String;
                      watch_close::Bool)::Nothing
    screen[].window_open[] || return nothing
    close(screen[])
    new_screen = GLMakie.Screen(visible = !controller.headless[], title = title)
    display(new_screen, fig)
    watch_close && watch_window_close!(controller, new_screen)
    screen[] = new_screen
    nothing
end

"The theme the session is drawn under."
get_theme(controller::ViewerController)::String = Themes.active()

"""
    switch_theme!(controller, name)

Draw the session under another theme, reporting what happened.

Both windows are rebuilt, since neither figure can be re-themed in place,
and the session is put back into them. The windows themselves are kept,
so they stay where the user put them on screen.
"""
function switch_theme!(controller::ViewerController, name::AbstractString)::String
    resolved = Themes.resolve(name)
    isnothing(resolved) && return Themes.unknown_theme_message(name)
    resolved == Themes.active() && return "Theme is already '$resolved'."
    session = capture_session(controller)
    Themes.activate!(resolved)
    # from here on this is a session starting up, in the order one does:
    # build, put on screen, wire up, reconcile -- and only then is the
    # captured session written into it, where the command line would be
    build_session!(controller)
    reattach_windows!(controller)
    connect_ui!(controller)
    notify(controller.ui.main_menu.variable_menu.selection)
    restore_session!(controller, session)
    update_plot_window_visibility!(controller)
    [wait(t) for t in controller.fd.tasks[]]
    "Theme: $resolved"
end

# ------------------------------------------------
#  Window Control
# ------------------------------------------------
function on_headless_change(controller::ViewerController)::Nothing
    controller.headless[] && return nothing
    # Open the menu window
    if haskey(controller.parsed_args, "menu") && controller.parsed_args["menu"]
        open_window!(controller, controller.menu_screen, controller.ui.menu, "CDFViewer - Menu")
    end
    # Open the figure window if a plot type is selected
    update_plot_window_visibility!(controller)
end

"Notice the user closing a window, on this screen and every replacement."
function watch_window_close!(controller::ViewerController,
                             screen::GLMakie.Screen)::Nothing
    on(screen.window_open) do is_open
        if !is_open
            on_fig_window_close(controller)
        end
    end
    nothing
end

function open_window!(controller::ViewerController,
        screen::Observable{GLMakie.Screen},
        fig::Figure,
        title::String)::Nothing
    # if the window is closed, properly close it and reopen
    if !screen[].window_open[]
        close(screen[])
        new_screen = GLMakie.Screen(visible = !controller.headless[], title = title)
        display(new_screen, fig)
        # set up the close event for the new screen
        watch_window_close!(controller, new_screen)

        screen[] = new_screen
        return nothing
    end

    !controller.headless[] && GLMakie.GLFW.ShowWindow(screen[].glscreen)
    nothing
end

function hide_window!(controller::ViewerController, screen::Observable{GLMakie.Screen})::Nothing
    # in headless mode, do nothing
    controller.headless[] && return nothing
    GLMakie.GLFW.HideWindow(screen[].glscreen)
    nothing
end

# ------------------------------------------------
#  Event handlers
# ------------------------------------------------

function on_variable_change(controller::ViewerController)::Nothing
    # make sure that the data is not updated while we change things
    controller.fd.plot_data.update_data_switch[] = false
    # Get the new variable and its dimensions
    new_var = controller.ui.main_menu.variable_menu.selection[]
    new_var_dims = Data.get_var_dims(controller.dataset, new_var)
    new_ndims = length(new_var_dims)
    new_dtype = eltype(controller.dataset.ds[new_var])
    # Set the new variable
    controller.ui.state.variable[] = new_var
    # Offer only partners the new variable can actually be drawn with
    update_partner_options!(controller)
    # Update the plot type options
    new_plot_options = Plotting.get_plot_options(new_ndims)
    fallback = Plotting.get_fallback_plot(new_ndims)
    # Check if the variable is non-numeric
    if new_dtype ∈ (String, Char)
        new_plot_options = [Constants.NOT_SELECTED_LABEL]
        fallback = Constants.NOT_SELECTED_LABEL
    end
    plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
    controller.watch_plot[] = false
    plot_type_menu.options[] = new_plot_options
    controller.watch_plot[] = true
    
    # Check if the new variable has enough dimensions for the current plot type
    if controller.ui.state.plot_type_name[] ∉ new_plot_options
        plot_type_menu.i_selected[] = findfirst(==(fallback), new_plot_options)
    else
        # Update the dimension selection
        plot_type_name = plot_type_menu.selection[]
        plot_ndims = Plotting.PLOT_TYPES[plot_type_name].ndims
        update_dim_selection_with_length!(controller, plot_ndims)
    end

    # Fill in (or drop) the second component for the settled plot type
    update_partner_variable!(controller)

    # Drop the overlays the new variable's axes no longer carry -- before
    # the switch goes back on, so no layer is ever re-read against axes it
    # does not span
    prune_layers!(controller)

    # Set the update switch back
    controller.fd.plot_data.update_data_switch[] = true

    # Update the axis limits to fit the new data
    isnothing(controller.fd.ax[]) || autolimits!(controller.fd.ax[])

    # Update the plot window visibility
    update_plot_window_visibility!(controller)
    nothing
end

function on_plot_type_change(controller::ViewerController)::Nothing
    !(controller.watch_plot[]) && return
    # make sure that the data is not updated while we change things
    controller.fd.plot_data.update_data_switch[] = false

    # Get the new plot type name
    plot_type_name = controller.ui.main_menu.plot_menu.plot_type.selection[]

    # if we have a dimension mismatch, change the dimension selection
    plot_ndims = Plotting.PLOT_TYPES[plot_type_name].ndims
    update_dim_selection_with_length!(controller, plot_ndims)

    # Set the new plot type
    controller.ui.state.plot_type_name[] = plot_type_name

    # A vector plot needs a second component; show its dropdown and fill
    # it in from the variable's name unless the user already picked one.
    update_partner_variable!(controller)

    # Delete the old axis and colorbar
    Plotting.clear_axis!(controller.fd)

    # Drop the overlays the new type cannot share an axis with
    prune_layers!(controller)

    # Set the update switch back
    controller.fd.plot_data.update_data_switch[] = true

    # Create the axis
    Plotting.create_axis!(controller.fd, controller.ui.state)

    # Update the plot window visibility
    update_plot_window_visibility!(controller)
    nothing
end

function on_dim_sel_change(controller::ViewerController)::Nothing
    !(controller.watch_dim[]) && return
    # make sure that the data is not updated while we change things
    controller.fd.plot_data.update_data_switch[] = false

    # Update the menus with the available dimensions
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
    coord_menus = controller.ui.main_menu.coord_menu.menus
    selected_dims = [m.selection[] for m in coord_menus]
    make_subset!(dims, selected_dims)
    # update the options in the menus
    set_menu_options!(controller, selected_dims)

    # If the number of selected dimensions does not match the plot type, change the plot type
    plot_ndims = controller.fd.plot_data.plot_type[].ndims
    if plot_ndims != length(selected_dims) && plot_ndims != 0
        new_plot = Plotting.get_dimension_plot(length(selected_dims))
        plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
        plot_type_menu.i_selected[] = findfirst(==(new_plot), plot_type_menu.options[])
    end

    # Delete the old axis and colorbar
    Plotting.clear_axis!(controller.fd)

    # Drop the overlays the new axes no longer carry
    prune_layers!(controller)

    # Set the update switch back
    controller.fd.plot_data.update_data_switch[] = true

    # Recreate the axis
    Plotting.create_axis!(controller.fd, controller.ui.state)
    nothing
end

function on_tick_event(controller::ViewerController, tick::Makie.Tick)::Nothing
    UI.update_slider!(controller.ui.main_menu.playback_menu, controller.ui.main_menu.coord_sliders)
    Plotting.rotate_camera!(controller.fd, tick.delta_time)
    nothing
end

function on_fig_window_close(controller::ViewerController)::Nothing
    # the app takes both windows down and puts them back up to swap a
    # rebuilt figure in; that is not the user closing the figure
    controller.watch_window[] || return nothing
    close(controller.fig_screen[])
    # select the "Select" option in the plot type menu
    plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
    plot_type_menu.i_selected[] = 1
    nothing
end

function on_save_event(controller::ViewerController)::Nothing
    controller.ui.state.plot_type_name[] == Constants.NOT_SELECTED_LABEL && return nothing
    Output.savefig(controller.fd.fig, controller.ui.state.output_settings[])
    update_plot_window_visibility!(controller)
    nothing
end

function on_record_event(controller::ViewerController)::Nothing
    controller.ui.state.plot_type_name[] == Constants.NOT_SELECTED_LABEL && return nothing
    ani_dim = controller.ui.main_menu.playback_menu.var.selection[]
    slider = controller.ui.main_menu.coord_sliders.sliders[ani_dim]
    slider_value = slider.value[]
    # a video must never rescale mid-file: make sure the pin is ready
    Plotting.update_colorrange!(controller.fd; sync = true)
    Output.record_scene(controller.fd.fig, controller.ui.state.output_settings[], slider)
    # reset the slider to its original value
    slider.value[] = slider_value
    update_plot_window_visibility!(controller)
    nothing
end

function on_export_event(controller::ViewerController)::Nothing
    exp_str = get_export_string(controller)
    @info "Commandline Arguments:\n$exp_str"
    nothing
end

function on_keyboard_event(controller::ViewerController)::Nothing
    fig = controller.fd.fig
    K = Makie.Keyboard
    keyevent = fig.scene.events.keyboardbutton[]

    # Control Modifier
    if K.left_control ∈ fig.scene.events.keyboardstate
        # i for interpolation
        if keyevent == Makie.KeyEvent(K.i, K.release)
            Plotting.update_interpolate!(controller.fd)
        end
    end
    nothing
end

# ------------------------------------------------
#  Vector plot components
# ------------------------------------------------

"""
    update_partner_options!(controller)

Offer the variables that can actually partner the selected one as a
second component -- every variable over the same dimensions -- and clear
the selection. A partner belongs to the variable it was picked for, so
moving to another variable drops it and lets the guess run again; an
explicit `v u,v` re-selects afterwards and wins.
"""
function update_partner_options!(controller::ViewerController)::Nothing
    menu = controller.ui.main_menu.variable2_menu
    variable = controller.ui.state.variable[]
    menu.i_selected[] = 1
    menu.options[] = [Constants.NOT_SELECTED_LABEL;
                      Data.vector_partner_options(controller.dataset, variable)]
    menu.i_selected[] = 1
    nothing
end

"""
    update_partner_variable!(controller)

Reconcile the second component with the selected plot type: a scalar type
hides the dropdown, a vector type shows it and -- unless a partner that
still fits is already picked -- guesses one from the variable's name.
"""
function update_partner_variable!(controller::ViewerController)::Nothing
    state = controller.ui.state
    main_menu = controller.ui.main_menu
    is_vector = Plotting.PLOT_TYPES[state.plot_type_name[]].nfields >= 2
    UI.show_variable2!(main_menu, is_vector)
    is_vector || return nothing
    dataset = controller.dataset
    Data.is_vector_partner(dataset, state.variable[], state.variable2[]) &&
        return nothing
    guess = Data.guess_vector_partner(dataset, state.variable[])
    menu = main_menu.variable2_menu
    idx = isnothing(guess) ? nothing : findfirst(==(guess), menu.options[])
    menu.i_selected[] = isnothing(idx) ? 1 : idx
    nothing
end

# ------------------------------------------------
#  Overlaid layers
# ------------------------------------------------
#
# The plotting layer owns the layers themselves; what it cannot reach are
# the menus. Adding or dropping one changes which dimensions the figure
# draws from, and with them which sliders are live and which axes playback
# can run along -- so every entry point that touches the layer list goes
# through here.

"Bring the sliders and the playback options in line with the layers."
function reconcile_layer_dims!(controller::ViewerController)::Nothing
    selected = controller.fd.plot_data.sel_dims[]
    set_slider_colors!(controller, selected)
    menu = controller.ui.main_menu.playback_menu.var
    previous = menu.selection[]
    set_playback_options!(controller, selected)
    # rebuilding the options can knock the selection off its dimension;
    # adding a layer must not move playback to another axis behind the
    # user's back
    if previous isa AbstractString && previous ∈ menu.options[] &&
       menu.selection[] != previous
        menu.i_selected[] = findfirst(==(previous), menu.options[])
    end
    nothing
end

function set_layer_variables!(controller::ViewerController, index::Int,
                              names::Vector{String})::String
    status = Plotting.set_layer_variables!(controller.fd, index, names)
    isempty(status) || reconcile_layer_dims!(controller)
    status
end

function set_layer_plot_type!(controller::ViewerController, index::Int,
                              name::String)::String
    status = Plotting.set_layer_plot_type!(controller.fd, index, name)
    isempty(status) || reconcile_layer_dims!(controller)
    status
end

function remove_layer!(controller::ViewerController, index::Int)::String
    status = Plotting.remove_layer!(controller.fd, index)
    isempty(status) || reconcile_layer_dims!(controller)
    status
end

"Drop the layers the base no longer supports, menus included."
function prune_layers!(controller::ViewerController)::Bool
    Plotting.prune_layers!(controller.fd) || return false
    reconcile_layer_dims!(controller)
    true
end

"""
    select_overlays!(controller)

Apply the repeatable `--over` / `--over-plot` arguments. The two are
matched by position: the n-th `--over` is drawn with the n-th
`--over-plot`, and an unmatched variable gets the default type for the
base it sits on.
"""
function select_overlays!(controller::ViewerController)::Nothing
    parsed_args = controller.parsed_args
    specs = get(parsed_args, "over", String[])
    types = get(parsed_args, "over-plot", String[])
    for (n, spec) in enumerate(specs)
        names = [String(strip(name)) for name in split(spec, ',')]
        index = Plotting.layer_count(controller.fd) + 1
        isempty(set_layer_variables!(controller, index, names)) && continue
        plot_type = n <= length(types) ? String(strip(types[n])) : ""
        isempty(plot_type) && continue
        set_layer_plot_type!(controller, index, plot_type)
    end
    nothing
end

"""
    select_variables!(controller, spec)

Apply a `-v` argument. A comma names the second component of a vector
plot ("u,v"); the partner is selected after the primary, so it survives
the option rebuild the primary triggers.
"""
function select_variables!(controller::ViewerController,
                           spec::AbstractString)::Nothing
    names = [String(strip(part)) for part in split(spec, ',')]
    filter!(!isempty, names)
    isempty(names) && return nothing
    var_menu = controller.ui.main_menu.variable_menu
    var = names[1]
    if var ∉ var_menu.options[]
        @warn "Variable '$var' not found in dataset. Available variables: $(var_menu.options[])"
        return nothing
    end
    var_menu.i_selected[] = findfirst(==(var), var_menu.options[])
    length(names) < 2 && return nothing
    partner_menu = controller.ui.main_menu.variable2_menu
    partner = names[2]
    if partner ∉ partner_menu.options[]
        @warn ("Variable '$partner' cannot be a second component of " *
               "'$var'. Available: $(partner_menu.options[][2:end])")
        return nothing
    end
    partner_menu.i_selected[] = findfirst(==(partner), partner_menu.options[])
    nothing
end

# ------------------------------------------------
#  Helper functions
# ------------------------------------------------
function update_plot_window_visibility!(controller::ViewerController)::Nothing
    if controller.ui.state.plot_type_name[] != Constants.NOT_SELECTED_LABEL
        open_window!(controller, controller.fig_screen, controller.fd.fig, "CDFViewer - Figure")
    else
        hide_window!(controller, controller.fig_screen)
    end
    nothing
end

function update_dim_selection_with_length!(controller::ViewerController, len::Int)::Nothing
    coord_menus = controller.ui.main_menu.coord_menu.menus
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
    selected_dims = String[m.selection[] for m in coord_menus if m.selection[] != Constants.NOT_SELECTED_LABEL]
    selected_dims = selected_dims[1:min(len, length(selected_dims))]
    make_subset!(dims, selected_dims)
    unused = setdiff(dims, selected_dims)
    selected_dims = [selected_dims; unused][1:len]
    set_menu_options!(controller, selected_dims)
    nothing
end

function make_subset!(dims::Vector{String}, selection::Vector{String})::Nothing
    filter!(!=(Constants.NOT_SELECTED_LABEL), unique!(selection))
    unused = setdiff(dims, selection)
    for (i, item) in enumerate(selection)
        if item ∉ dims
            selection[i] = popfirst!(unused)
        end
    end
    nothing
end

function set_slider_inactive!(coord_slider::UI.CoordinateSliders, dim::String)::Nothing
    colors = Themes.theme_colors()
    inactive_text = colors.inactive_text
    inactive_slider = colors.inactive_slider_bar

    coord_slider.labels[dim].color[] = inactive_text
    coord_slider.valuelabels[dim].color[] = inactive_text
    coord_slider.sliders[dim].color_active[] = inactive_text
    coord_slider.sliders[dim].color_active_dimmed[] = inactive_slider
    coord_slider.sliders[dim].color_inactive[] = inactive_slider
    nothing
end

function set_slider_active!(coord_slider::UI.CoordinateSliders, dim::String)::Nothing
    colors = Themes.theme_colors()
    active_text = colors.text
    inactive_slider = colors.inactive_slider_bar
    accent = colors.accent
    accent_dimmed = colors.accent_dimmed

    coord_slider.labels[dim].color[] = active_text
    coord_slider.valuelabels[dim].color[] = active_text
    coord_slider.sliders[dim].color_active[] = accent
    coord_slider.sliders[dim].color_active_dimmed[] = accent_dimmed
    coord_slider.sliders[dim].color_inactive[] = inactive_slider
    nothing
end

"""
    drawn_dims(controller)

Every dimension the figure draws from, over all its layers. An overlay may
span a dimension the base does not, and that dimension is just as much a
slider and just as much a playback axis -- a layer without it simply does
not move.
"""
function drawn_dims(controller::ViewerController)::Vector{String}
    dataset = controller.dataset
    dims = String[]
    for i in eachindex(controller.fd.plot_data.layers)
        for variable in Plotting.layer_variables(controller.fd, i)
            haskey(dataset.var_coords, variable) || continue
            append!(dims, Data.get_var_dims(dataset, variable))
        end
    end
    unique!(dims)
end

function set_slider_colors!(controller::ViewerController, selected_dims::Vector{String})::Nothing
    coord_slider = controller.ui.main_menu.coord_sliders
    var_dims = drawn_dims(controller)
    unused_dims = setdiff(var_dims, selected_dims)
    for dim in keys(coord_slider.sliders)
        if dim in unused_dims
            set_slider_active!(coord_slider, dim)
        else
            set_slider_inactive!(coord_slider, dim)
        end
    end
    nothing
end

function select_default_playback_dim!(controller::ViewerController)::Nothing
    menu = controller.ui.main_menu.playback_menu.var
    options = menu.options[]
    if "time" ∈ options
        menu.i_selected[] = findfirst(==("time"), options)
    else
        # default to the last option
        menu.i_selected[] = length(options)
    end
    nothing
end

function set_playback_options!(controller::ViewerController, selected_dims::Vector{String})::Nothing
    menu = controller.ui.main_menu.playback_menu.var
    toggle = controller.ui.main_menu.playback_menu.toggle
    var_dims = drawn_dims(controller)
    unused_dims = setdiff(var_dims, selected_dims)
    if menu.i_selected[] > length(unused_dims) + 1
        if toggle.active[]
            toggle.active[] = false
        end
        menu.i_selected[] = 1
    end
    menu.options[] = [Constants.NOT_SELECTED_LABEL; unused_dims...]
    if menu.i_selected[] ∈ [0, 1]
        if toggle.active[]
            toggle.active[] = false
        end
        select_default_playback_dim!(controller)
    end
    nothing
end

function set_menu_options!(controller::ViewerController, selected_dims::Vector{String})::Nothing
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])

    controller.watch_dim[] = false
    for (i, menu) in enumerate(controller.ui.main_menu.coord_menu.menus)
        menu.i_selected[] = 1
        menu.options[] = [Constants.NOT_SELECTED_LABEL; dims...]
        menu.i_selected[] = 1
        if i ≤ length(selected_dims)
            menu.i_selected[] = findfirst(==(selected_dims[i]), menu.options[])
        end
    end
    controller.watch_dim[] = true

    # Sync the state with the menu selections
    UI.sync_dim_selections!(controller.ui.state, controller.ui.main_menu.coord_menu)
    # Update the slider colors
    set_slider_colors!(controller, selected_dims)
    # Update the playback options
    set_playback_options!(controller, selected_dims)
    nothing
end

function get_export_string(controller::ViewerController)::String
    state = controller.ui.state
    exp = ""
    # get the variable, plus the second component of a vector plot -- one
    # comma-separated token, so it survives as a single shell argument
    var = state.variable[]
    exp *= "-v$var"
    if Plotting.PLOT_TYPES[state.plot_type_name[]].nfields >= 2 &&
       Data.is_vector_partner(controller.dataset, var, state.variable2[])
        exp *= "," * state.variable2[]
    end
    # get the axis dimensions
    for (axis, dim) in zip(("x", "y", "z"), (state.x_name[], state.y_name[], state.z_name[]))
        if dim != Constants.NOT_SELECTED_LABEL
            exp *= " -$axis$dim"
        end
    end
    # get the plot type
    plot_type = state.plot_type_name[]
    if plot_type != Constants.NOT_SELECTED_LABEL
        exp *= " -p$plot_type"
    end
    # get the overlaid layers -- one --over/--over-plot pair each, in the
    # order they are drawn, which is the order they are read back in
    for i in 2:Plotting.layer_count(controller.fd)
        exp *= " --over=" * join(Plotting.layer_variables(controller.fd, i), ",")
        exp *= " --over-plot=" * Plotting.layer_plot(controller.fd, i).type
    end
    # get the dimensions (only those that are relevant)
    var_dims = drawn_dims(controller)
    coord_menus = controller.ui.main_menu.coord_menu.menus
    selected_dims = [m.selection[] for m in coord_menus]
    unused_dims = setdiff(var_dims, selected_dims)
    dim_strs = String[]
    for dim in unused_dims
        id = state.dim_obs[][dim]
        if id != 1
            push!(dim_strs, "$dim=$id")
        end
    end
    if !isempty(dim_strs)
        exp *= " --dims=" * join(dim_strs, ",")
    end
    # get the animation dimension
    ani_dim = controller.ui.main_menu.playback_menu.var.selection[]
    if ani_dim != Constants.NOT_SELECTED_LABEL
        exp *= " -a$ani_dim"
    end
    # get the plot kwargs
    Plotting.fix_figure_kwargs!(controller.fd) # make sure to save figsize and limits
    kwargs = state.kwargs[]
    text = Plotting.kwarg_dict_to_string(kwargs)
    if !isempty(text)
        exp *= " --kwargs='$text'"
    end
    # get the saveoptions
    text = get_save_option_string(controller)
    if !isempty(text)
        exp *= " --saveoptions='$text'"
    end
    # get the theme, unless it is the one a restart picks anyway
    theme = get_theme(controller)
    if theme != Themes.DEFAULT_THEME
        exp *= " --theme=$theme"
    end

    exp
end

"The save options as a `-s` line, empty when a restart sets them anyway."
get_save_option_string(controller::ViewerController)::String =
    Output.settings_string(controller.ui.state.output_settings[];
                           filename = get_standard_filename(controller.parsed_args))

function get_standard_filename(parsed_args::Union{Nothing,Dict})::String
    # no command line to take a name from -- a controller built by hand
    # carries an empty argument dict
    (isnothing(parsed_args) || !haskey(parsed_args, "files")) && return "output"
    datafile = parsed_args["files"][1]
    splitext(basename(datafile))[1]
end


end # module