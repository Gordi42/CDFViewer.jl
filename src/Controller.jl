module Controller

using Colors
using GLMakie
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting

struct ViewerController
    ui::UI.UIElements
    fd::Plotting.FigureData
    dataset::Data.CDFDataset
    watch_dim::Observable{Bool}
    watch_plot::Observable{Bool}
end

function on_variable_change(controller::ViewerController)
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
        new_plot_options = ["Info"]
        fallback = "Info"
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
end

function on_plot_type_change(controller::ViewerController)
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
end

function update_dim_selection_with_length!(controller::ViewerController, len::Int)
    coord_menus = controller.ui.coord_menu.menus
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
    selected_dims = String[m.selection[] for m in coord_menus if m.selection[] != "Not Selected"]
    selected_dims = selected_dims[1:min(len, length(selected_dims))]
    make_subset!(dims, selected_dims)
    unused = setdiff(dims, selected_dims)
    selected_dims = [selected_dims; unused][1:len]
    set_menu_options!(controller, selected_dims)
end

function make_subset!(dims::Vector{String}, selection::Vector{String})
    filter!(!=("Not Selected"), unique!(selection))
    unused = setdiff(dims, selection)
    for (i, item) in enumerate(selection)
        if item ∉ dims
            selection[i] = popfirst!(unused)
        end
    end
end

function set_slider_inactive!(coord_slider::UI.CoordinateSliders, dim::String)
    inactive_text_color = parse(Colorant, :lightgray)
    inactive_slider_bar_color = RGBf(0.94, 0.94, 0.94)

    coord_slider.labels[dim].color[] = inactive_text_color
    coord_slider.valuelabels[dim].color[] = inactive_text_color
    coord_slider.sliders[dim].color_active[] = inactive_text_color
    coord_slider.sliders[dim].color_active_dimmed[] = inactive_slider_bar_color
    coord_slider.sliders[dim].color_inactive[] = inactive_slider_bar_color
end

function set_slider_active!(coord_slider::UI.CoordinateSliders, dim::String)
    active_text_color = parse(Colorant, :black)
    inactive_slider_bar_color = RGBf(0.94, 0.94, 0.94)

    coord_slider.labels[dim].color[] = active_text_color
    coord_slider.valuelabels[dim].color[] = active_text_color
    coord_slider.sliders[dim].color_active[] = Makie.COLOR_ACCENT[]
    coord_slider.sliders[dim].color_active_dimmed[] = Makie.COLOR_ACCENT_DIMMED[]
    coord_slider.sliders[dim].color_inactive[] = inactive_slider_bar_color
end

function set_slider_colors!(controller::ViewerController, selected_dims::Vector{String})
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
end

function set_menu_options!(controller::ViewerController, selected_dims::Vector{String})
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])

    controller.watch_dim[] = false
    for (i, menu) in enumerate(controller.ui.coord_menu.menus)
        menu.i_selected[] = 1
        menu.options[] = ["Not Selected"; dims...]
        menu.i_selected[] = 1
        if i ≤ length(selected_dims)
            menu.i_selected[] = findfirst(==(selected_dims[i]), menu.options[])
        end
    end
    controller.watch_dim[] = true

    # Sync the state with the menu selections
    UI.sync_dim_selections!(controller.ui.state, controller.ui.coord_menu)
    # Update the slider colors
    set_slider_colors!(controller, selected_dims)
end

function on_dim_sel_change(controller::ViewerController)
    !(controller.watch_dim[]) && return
    # make sure that the data is not updated while we change things
    controller.fd.plot_data.update_data_switch[] = false

    # Update the menus with the available dimensions
    dims = Data.get_var_dims(controller.dataset, controller.ui.state.variable[])
    coord_menus = controller.ui.coord_menu.menus
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
end

function on_tick_event(controller::ViewerController, tick::Makie.Tick)
end

function init_controller(dataset::Data.CDFDataset)
    fig = Plotting.create_figure()
    ui = UI.UIElements(fig, dataset)
    plot_data = Plotting.init_plot_data(ui.state, dataset)
    fig_data = Plotting.init_figure_data(fig, plot_data, ui.state)
    controller = ViewerController(ui, fig_data, dataset, Observable(true), Observable(true))
    controller
end

function setup_controller!(controller::ViewerController)
    # Helper to convert functions to event handlers
    conv = func -> (_ -> func(controller))

    # Connect UI changes to controller functions
    on(conv(on_variable_change), controller.ui.main_menu.variable_menu.selection)
    on(conv(on_plot_type_change), controller.ui.main_menu.plot_menu.plot_type.selection)
    for menu in controller.ui.coord_menu.menus
        on(conv(on_dim_sel_change), menu.selection)
    end
    on(tick -> on_tick_event(controller, tick), controller.fd.fig.scene.events.tick)

    notify(controller.ui.main_menu.variable_menu.selection)

    # set the initial plot type
    ndims = length(Data.get_var_dims(controller.dataset, controller.ui.state.variable[]))
    fallback = Plotting.get_fallback_plot(ndims)
    plot_type_menu = controller.ui.main_menu.plot_menu.plot_type
    if fallback ∈ plot_type_menu.options[]
        plot_type_menu.i_selected[] = findfirst(==(fallback), plot_type_menu.options[])
    end
end

function create_controller(dataset::Data.CDFDataset)
    controller = init_controller(dataset)
    setup_controller!(controller)
    controller
end

end # module