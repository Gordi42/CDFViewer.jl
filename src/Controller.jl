module Controller

using Colors
using GLMakie
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting

struct ViewerController
    ui::UI.UIElements
    fd::Plotting.FigureData
    dataset::Data.CDFDataset
    watch_dim::Observable{Bool}
    watch_plot::Observable{Bool}
    menu_screen::Observable{GLMakie.Screen}
    fig_screen::Observable{GLMakie.Screen}
    visible::Bool
end

function ViewerController(dataset::Data.CDFDataset; visible::Bool = false)::ViewerController
    ui = UI.UIElements(dataset)
    plot_data = Plotting.PlotData(ui.state, dataset)
    fig_data = Plotting.FigureData(plot_data, ui.state)
    menu_screen = GLMakie.Screen(visible = visible)
    fig_screen = GLMakie.Screen(visible = false)  # Start hidden
    display(menu_screen, ui.menu)
    display(fig_screen, fig_data.fig)

    controller = ViewerController(
        ui, fig_data, dataset,
        Observable(true), Observable(true),
        Observable(menu_screen), Observable(fig_screen), visible)
    setup!(controller)
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

    # This will set everything up for the initial variable
    notify(controller.ui.main_menu.variable_menu.selection)

    # return the controller
    controller
end

# ------------------------------------------------
#  Window Control
# ------------------------------------------------
function open_window!(controller::ViewerController,
        screen::Observable{GLMakie.Screen},
        fig::Figure)::Nothing
    # if the window is closed, properly close it and reopen
    if !screen[].window_open[]
        close(screen[])
        new_screen = GLMakie.Screen(visible = controller.visible)
        display(new_screen, fig)
        screen[] = new_screen
        return nothing
    end

    controller.visible && GLMakie.GLFW.ShowWindow(screen[].glscreen)
    nothing
end

function hide_window!(controller::ViewerController, screen::Observable{GLMakie.Screen})::Nothing
    # in headless mode, do nothing
    controller.visible || return nothing
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
    if plot_ndims != length(selected_dims)
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

# ------------------------------------------------
#  Helper functions
# ------------------------------------------------
function update_plot_window_visibility!(controller::ViewerController)::Nothing
    if controller.ui.state.plot_type_name[] != Constants.NOT_SELECTED_LABEL
        open_window!(controller, controller.fig_screen, controller.fd.fig)
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


end # module