module Controller

using Colors
using Printf
using GLMakie
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Parsing

struct ViewerController
    ui::UI.UIElements
    fd::Plotting.FigureData
    dataset::Data.CDFDataset
    watch_dim::Observable{Bool}
    watch_plot::Observable{Bool}
    menu_screen::Observable{GLMakie.Screen}
    fig_screen::Observable{GLMakie.Screen}
    headless::Observable{Bool}
    parsed_args::Union{Nothing,Dict}
end

function ViewerController(dataset::Data.CDFDataset;
    headless::Bool = true, parsed_args::Union{Nothing,Dict}=nothing)::ViewerController
    ui = UI.UIElements(dataset)
    plot_data = Plotting.PlotData(ui.state, dataset)
    fig_data = Plotting.FigureData(plot_data, ui.state)
    menu_screen = GLMakie.Screen(visible = false, title = "CDFViewer - Menu") # Start hidden
    fig_screen = GLMakie.Screen(visible = false, title = "CDFViewer - Figure")  # Start hidden
    display(menu_screen, ui.menu)
    display(fig_screen, fig_data.fig)
    parsed_args = isnothing(parsed_args) ? Dict() : parsed_args

    controller = ViewerController(
        ui, fig_data, dataset,
        Observable(true), Observable(true),
        Observable(menu_screen), Observable(fig_screen), Observable(true),
        parsed_args
    )
    setup!(controller)
    # wait until the tasks are done
    [wait(t) for t in controller.fd.tasks[]]
    controller.headless[] = headless
    controller
end

function setup!(controller::ViewerController)::ViewerController
    # Helper to convert functions to event handlers
    conv = func -> (_ -> func(controller))

    # Connect UI changes to controller functions
    on(conv(on_variable_change), controller.ui.main_menu.variable_menu.selection)
    on(conv(on_plot_type_change), controller.ui.main_menu.plot_menu.plot_type.selection)
    for menu in controller.ui.main_menu.coord_menu.menus
        on(conv(on_dim_sel_change), menu.selection)
    end
    on(tick -> on_tick_event(controller, tick), controller.fd.fig.scene.events.tick)

    on(controller.fig_screen[].window_open) do is_open
        if !is_open
            on_fig_window_close(controller)
        end
    end
    on(conv(on_save_event), controller.ui.main_menu.export_menu.save_button.clicks)
    on(conv(on_record_event), controller.ui.main_menu.export_menu.record_button.clicks)
    on(conv(on_export_event), controller.ui.main_menu.export_menu.export_button.clicks)
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
    # Set the variable if provided
    if haskey(parsed_args, "var") && parsed_args["var"] != ""
        var = parsed_args["var"]
        var_menu = controller.ui.main_menu.variable_menu
        if var in var_menu.options[]
            var_menu.i_selected[] = findfirst(==(var), var_menu.options[])
        else
            available_vars = var_menu.options[]
            @warn "Variable '$var' not found in dataset. Available variables: $(available_vars)"
        end
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

    # Process the work path if provided
    if haskey(parsed_args, "path") && parsed_args["path"] != ""
        path = parsed_args["path"]
        if !isdir(dirname(path))
            @warn "Directory for path '$path' does not exist."
        else
            controller.ui.state.save_path[] = path
        end
    end

    # Process kwargs if provided
    if haskey(parsed_args, "kwargs") && parsed_args["kwargs"] != ""
        textbox = controller.ui.main_menu.plot_menu.plot_kw
        textbox.displayed_string = parsed_args["kwargs"]
        textbox.stored_string = parsed_args["kwargs"]
    end

    # Process saveoptions if provided
    if haskey(parsed_args, "saveoptions") && parsed_args["saveoptions"] != ""
        textbox = controller.ui.main_menu.export_menu.options
        textbox.displayed_string = parsed_args["saveoptions"]
        textbox.stored_string = parsed_args["saveoptions"]
    end

    nothing
end

# ------------------------------------------------
#  Window Control
# ------------------------------------------------
function on_headless_change(controller::ViewerController)::Nothing
    controller.headless[] && return nothing
    # Open the menu window
    if haskey(controller.parsed_args, "no-menu") && controller.parsed_args["no-menu"]
        # Do not open the menu
    else
        open_window!(controller, controller.menu_screen, controller.ui.menu, "CDFViewer - Menu")
    end
    # Open the figure window if a plot type is selected
    update_plot_window_visibility!(controller)
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
        on(new_screen.window_open) do is_open
            if !is_open
                on_fig_window_close(controller)
            end
        end

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

    # Delete the old axis and colorbar
    Plotting.clear_axis!(controller.fd)

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


    # Set the update switch back
    controller.fd.plot_data.update_data_switch[] = true

    # Update the axis limits to fit the new data
    isnothing(controller.fd.ax[]) || autolimits!(controller.fd.ax[])
    nothing
end

function on_tick_event(controller::ViewerController, tick::Makie.Tick)::Nothing
    UI.update_slider!(controller.ui.main_menu.playback_menu, controller.ui.main_menu.coord_sliders)
    nothing
end

function on_fig_window_close(controller::ViewerController)::Nothing
    close(controller.fig_screen[])
    # select the "Select" option in the plot type menu
    plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
    plot_type_menu.i_selected[] = 1
    nothing
end

function on_save_event(controller::ViewerController)::Nothing
    # TODO
    @warn "Figure saving not implemented yet."
    nothing
end

function on_record_event(controller::ViewerController)::Nothing
    # TODO
    @warn "Animation recording not implemented yet."
    nothing
end

function on_export_event(controller::ViewerController)::Nothing
    exp_str = get_export_string(controller)
    println("Export command arguments:")
    println(exp_str)
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
    inactive_text = Constants.THEME_LIGHT.inactive_text_color
    inactive_slider = Constants.THEME_LIGHT.inactive_slider_bar_color

    coord_slider.labels[dim].color[] = inactive_text
    coord_slider.valuelabels[dim].color[] = inactive_text
    coord_slider.sliders[dim].color_active[] = inactive_text
    coord_slider.sliders[dim].color_active_dimmed[] = inactive_slider
    coord_slider.sliders[dim].color_inactive[] = inactive_slider
    nothing
end

function set_slider_active!(coord_slider::UI.CoordinateSliders, dim::String)::Nothing
    active_text = Constants.THEME_LIGHT.active_text_color
    inactive_slider = Constants.THEME_LIGHT.inactive_slider_bar_color
    accent = Constants.THEME_LIGHT.accent_color
    accent_dimmed = Constants.THEME_LIGHT.accent_dimmed_color

    coord_slider.labels[dim].color[] = active_text
    coord_slider.valuelabels[dim].color[] = active_text
    coord_slider.sliders[dim].color_active[] = accent
    coord_slider.sliders[dim].color_active_dimmed[] = accent_dimmed
    coord_slider.sliders[dim].color_inactive[] = inactive_slider
    nothing
end

function set_slider_colors!(controller::ViewerController, selected_dims::Vector{String})::Nothing
    coord_slider = controller.ui.main_menu.coord_sliders
    var_dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
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
    var_dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
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
    # get the variable
    var = state.variable[]
    exp *= "-v$var"
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
    # get the dimensions (only those that are relevant)
    var_dims = Data.get_var_dims(controller.dataset, var)
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
    text = state.plot_kw[]
    text = isnothing(text) ? "" : strip(text)
    keywords = Parsing.parse_kwargs(text)
    additional_kwargs = get_figure_kwargs(controller) # Dict of symbol => value
    if !isempty(additional_kwargs)
        for (k,v) in additional_kwargs
            # check if k already exists in keywords
            if !haskey(keywords, Symbol(k))
                if !isempty(text)
                    text *= ", "
                end
                text *= "$k=$v"
            end
        end
    end
    if !isempty(text)
        exp *= " --kwargs='$text'"
    end
    # get the saveoptions
    text = controller.ui.main_menu.export_menu.options.stored_string[]
    if !isnothing(text) && !isempty(text)
        exp *= " --saveoptions='$text'"
    end
    # get the path
    path = state.save_path[]
    if !isempty(path)
        exp *= " --path=$path"
    end
    
    exp
end

function get_figure_kwargs(controller::ViewerController)::Dict{String,Any}
    controller.ui.state.plot_type_name[] == Constants.NOT_SELECTED_LABEL && return Dict{String,Any}()
    kwargs = Dict{String,Any}()

    # figsize
    figwidths = controller.fd.fig.scene.viewport[].widths
    figsize = (figwidths[1], figwidths[2])
    if figsize != Constants.FIGSIZE
        println("Figsize: ", figsize)
        kwargs["figsize"] = (figwidths[1], figwidths[2])
    end

    # axis limits
    ax = controller.fd.ax[]
    if !isnothing(ax)
        kwargs["limits"] = get_limit_string(controller)
    end

    # 3D axis orientation
    if ax isa Axis3
        kwargs["azimuth"] = @sprintf("%g", ax.azimuth[])
        kwargs["elevation"] = @sprintf("%g", ax.elevation[])
    end
    kwargs
end

function get_limit_string(controller::Controller.ViewerController)::String
    ax = controller.fd.ax[]

    lim_rect = ax.finallimits[]
    limits = Float64[]
    # Loop through each dimension
    for dim in 1:length(lim_rect.origin)
        # Add min limit (origin)
        push!(limits, lim_rect.origin[dim])
        # Add max limit (origin + width)
        push!(limits, lim_rect.origin[dim] + lim_rect.widths[dim])
    end

    lim_strings = [@sprintf("%g", value) for value in limits]
    "(" * join(lim_strings, ", ") * ")"
end

end # module