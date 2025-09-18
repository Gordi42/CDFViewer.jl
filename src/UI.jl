module UI

using DataStructures
using GLMakie

import ..Constants
import ..Interpolate
import ..Data
import ..Output

# ============================================
#  Plot Menu
# ============================================

struct PlotMenu
    plot_type::Menu
    plot_kw::Textbox
    fig::Figure
end

function PlotMenu(fig::Figure)::PlotMenu
    PlotMenu(
        Menu(fig, options=[Constants.NOT_SELECTED_LABEL]),
        Textbox(
            fig,
            placeholder = Constants.PLOT_KW_HINTS,
            tellwidth = false,
            width = Relative(1),
            defocus_on_submit = false,
            halign = :left,
        ),
        fig,
    )
end

function layout(plot_menu::PlotMenu)::GridLayout
    vgrid!(
        hgrid!(
            Label(plot_menu.fig, L"\textbf{Plot Settings}", width = nothing),
            plot_menu.plot_type),
        plot_menu.plot_kw,
    )
end

# ============================================
#  Export Menu
# ============================================
struct ExportMenu
    save_button::Button
    record_button::Button
    export_button::Button
    options::Textbox
    fig::Figure
end

function ExportMenu(fig::Figure)::ExportMenu
    ExportMenu(
        Button(fig, label = "Save", tellwidth = false, width = Relative(1)),
        Button(fig, label = "Record", tellwidth = false, width = Relative(1)),
        Button(fig, label = "Export", tellwidth = false, width = Relative(1)),
        Textbox(
            fig,
            placeholder = "e.g., filename=\"output.png\", dpi=300",
            tellwidth = false,
            width = Relative(1),
            defocus_on_submit = false,
            halign = :left,
        ),
        fig,
    )
end

function layout(export_menu::ExportMenu)::GridLayout
    vgrid!(
        hgrid!(
            export_menu.save_button,
            export_menu.record_button,
            export_menu.export_button,
        ),
        export_menu.options,
    )
end

# ============================================
#  Coordinate Sliders
# ============================================
struct CoordinateSliders
    sliders::Dict{String, Slider}
    continuous_values::Dict{String, Observable{Float64}}
    labels::Dict{String, Label}
    valuelabels::Dict{String, Label}
    slider_grid::SliderGrid
    auto_update::Toggle
    fig::Figure
end

function CoordinateSliders(fig::Figure, dataset::Data.CDFDataset)::CoordinateSliders
    # align the toggle to the right
    auto_update = Toggle(fig, active = false, halign = :right)
    coord_sliders = SliderGrid(fig,[
        (label=dim,
        range=1:length(Data.get_dim_values(dataset, dim)),
        startvalue=1, update_while_dragging=auto_update.active)
        for dim in dataset.coordinates]...)
    labels = Dict(
        dim => coord_sliders.labels[i] for (i, dim) in enumerate(dataset.coordinates))
    sliders = Dict(
        dim => coord_sliders.sliders[i] for (i, dim) in enumerate(dataset.coordinates))
    valuelabels = Dict(
        dim => coord_sliders.valuelabels[i] for (i, dim) in enumerate(dataset.coordinates))

    continuous_slider = Dict(key => @lift(float.($(val.value))) for (key, val) in sliders)
    for key in keys(sliders)
        on(continuous_slider[key]) do v
            set_close_to!(sliders[key], v)
        end
    end

    CoordinateSliders(sliders, continuous_slider, labels, valuelabels, coord_sliders, auto_update, fig)
end

function layout(coord_sliders::CoordinateSliders)::GridLayout
    vgrid!(
        hgrid!(
            Label(coord_sliders.fig, L"\textbf{Fixed Coordinates}", width = nothing),
            coord_sliders.auto_update
        ),
        coord_sliders.slider_grid,
    )
end

# ============================================
#  Playback Menu
# ============================================

struct PlaybackMenu
    toggle::Toggle
    speed::Slider
    var::Menu
    label::Label
    fig::Figure
end

function PlaybackMenu(fig::Figure, dataset::Data.CDFDataset, coord_sliders::Dict{String, Slider})::PlaybackMenu
    toggle = Toggle(fig, active = false)
    speed_slider = Slider(fig, range = -2.0:0.05:1, startvalue = 0.0)
    var_menu = Menu(fig,
                    options = [Constants.NOT_SELECTED_LABEL; dataset.coordinates],
                    tellwidth = false)
    # Create the label that shows the current value of the selected dimension
    label = Label(fig, Constants.NO_DIM_SELECTED_LABEL, halign = :left, tellwidth = false)
    slider_values = [slider.value for slider in values(coord_sliders)]

    for trigger in (var_menu.selection, slider_values...)
        on(trigger) do _
            dim = var_menu.selection[]
            if isnothing(dim)
                label.text[] = Constants.NO_DIM_SELECTED_LABEL
            elseif dim == Constants.NOT_SELECTED_LABEL
                label.text[] = Constants.NO_DIM_SELECTED_LABEL
            else
                idx = coord_sliders[dim].value[]
                label.text[] = Data.get_dim_value_label(dataset, dim, idx)
            end
        end
    end
    notify(var_menu.selection)
    PlaybackMenu(toggle, speed_slider, var_menu, label, fig)
end

function layout(playback_menu::PlaybackMenu)::GridLayout
    vgrid!(
        hgrid!(
            Label(playback_menu.fig, L"\textbf{Play}", width = 30), 
            playback_menu.toggle,
            playback_menu.speed,
            playback_menu.var,
        ),
        playback_menu.label,
    )
end

function update_slider!(playback_menu::PlaybackMenu, coord_sliders::CoordinateSliders)::Nothing
    playback_menu.toggle.active[] || return
    dim = playback_menu.var.selection[]
    dim == Constants.NOT_SELECTED_LABEL && return

    dt = 10^playback_menu.speed.value[]
    current_value = coord_sliders.continuous_values[dim][]
    new_value = (current_value + dt)
    if new_value > maximum(coord_sliders.sliders[dim].range[])
        new_value = minimum(coord_sliders.sliders[dim].range[])
    end
    set_close_to!(coord_sliders.sliders[dim], new_value)
    coord_sliders.continuous_values[dim][] = new_value
    nothing
end

# ============================================
#  Coordinate Menu
# ============================================

struct CoordinateMenu
    labels::Vector{Label}
    menus::Vector{Menu}
    fig::Figure
end

function CoordinateMenu(fig::Figure)::CoordinateMenu
    dimension_selections = [
        Menu(fig, options = [Constants.NOT_SELECTED_LABEL], tellwidth = false)
        for i in 1:3
    ]
    dimension_labels = [Label(fig, label) for label in Constants.DIMENSION_LABELS]
    CoordinateMenu(dimension_labels, dimension_selections, fig)
end

function layout(coord_menu::CoordinateMenu)::GridLayout
    hgrid!([hgrid!(coord_menu.labels[i], coord_menu.menus[i]) for i in 1:3]...)
end

# ============================================
#  Main Menu
# ============================================

struct MainMenu
    variable_menu::Menu
    plot_menu::PlotMenu
    playback_menu::PlaybackMenu
    coord_menu::CoordinateMenu
    coord_sliders::CoordinateSliders
    export_menu::ExportMenu
    fig::Figure
end

function MainMenu(fig::Figure, dataset::Data.CDFDataset)::MainMenu
    variable_menu = Menu(fig, options = dataset.variables)
    plot_menu = PlotMenu(fig)
    coord_sliders = CoordinateSliders(fig, dataset)
    playback_menu = PlaybackMenu(fig, dataset, coord_sliders.sliders)
    coord_menu = CoordinateMenu(fig)
    export_menu = ExportMenu(fig)
    MainMenu(variable_menu, plot_menu, playback_menu, coord_menu, coord_sliders, export_menu, fig)
end

function layout(main_menu::MainMenu)::GridLayout
    vgrid!(
        Label(main_menu.fig, L"\textbf{CDF Viewer}", halign = :center, fontsize=30, tellwidth=false),
        hgrid!(Label(main_menu.fig, L"\textbf{Variable}", width = nothing), main_menu.variable_menu),
        layout(main_menu.plot_menu),
        layout(main_menu.coord_menu),
        layout(main_menu.playback_menu),
        layout(main_menu.coord_sliders),
        layout(main_menu.export_menu),
    )
end


# ============================================
#  All Variables Controlled By the UI
# ============================================

struct State
    variable::Observable{String}
    plot_type_name::Observable{String}
    x_name::Observable{String}
    y_name::Observable{String}
    z_name::Observable{String}
    dim_obs::Observable{Dict{String, Int}}
    kwargs::Observable{OrderedDict{Symbol, Any}}
    output_settings::Observable{Output.OutputSettings}
    range_control::Observable{Union{Nothing, Interpolate.RangeControl}}
end

function State(main_menu::MainMenu)::State
    # Create an observable dictionary that tracks the values of all sliders
    slider_values = Dict(dim => slider.value for (dim, slider) in main_menu.coord_sliders.sliders)
    dim_obs = Observable(Dict(dim => value[] for (dim, value) in slider_values))
    output_settings = Observable(Output.OutputSettings("output"))

    # Set up listeners to update the dictionary when any slider changes
    for (dim, value_obs) in slider_values
        on(value_obs) do v
            dim_obs[][dim] = v
            notify(dim_obs)
        end
    end

    # Set up listeners to update the output settings when the export options change
    on(main_menu.export_menu.options.stored_string) do s
        Output.apply_settings_string!(output_settings[], s)
        notify(output_settings)
    end
        

    State(
        Observable(main_menu.variable_menu.selection[]),
        Observable(main_menu.plot_menu.plot_type.selection[]),
        Observable(main_menu.coord_menu.menus[1].selection[]),
        Observable(main_menu.coord_menu.menus[2].selection[]),
        Observable(main_menu.coord_menu.menus[3].selection[]),
        dim_obs,
        Observable(OrderedDict{Symbol, Any}()),
        output_settings,
        Observable(nothing),
    )
end

function sync_dim_selections!(state::State, coord_menu::CoordinateMenu)::Nothing
    state.x_name[] = coord_menu.menus[1].selection[]
    state.y_name[] = coord_menu.menus[2].selection[]
    state.z_name[] = coord_menu.menus[3].selection[]
    nothing
end

# ============================================
#  All UI Elements
# ============================================

struct UIElements
    main_menu::MainMenu
    state::State
    menu::Figure
end

function UIElements(dataset::Data.CDFDataset)::UIElements
    # Initialize the menu figure
    menu = Figure(size = (400, 100))

    # Initialize the menus
    main_menu = MainMenu(menu, dataset)
    # Initialize the UI state
    state = State(main_menu)
    state.range_control[] = dataset.interp.rc
    # Put the menus in the figure
    menu[1, 1] = layout(main_menu)
    # Resize the window to fit the content
    resize_to_layout!(menu)
    # Return the UI elements
    UIElements(main_menu, state, menu)
end

function compute_height(num_vars::Int)::Int
    base_height = 340  # Base height for the fixed elements
    per_var_height = 40 # Additional height per variable
    base_height + num_vars * per_var_height
end

function update_coord_ranges!(
    ui::UIElements,
    property::Symbol,
    new_range::Union{AbstractArray, Tuple{Real, Real, Real}, Nothing},
    update_switch::Observable{Bool},
    )::Nothing
    # Disable Updates
    old_update = update_switch[]
    update_switch[] = false
    # Get the name of the property
    prop_name = String(property)
    try
        # If the new_range is a tuple with three elements, convert it to a LinRange
        if isa(new_range, Tuple) && length(new_range) == 3
            new_range = LinRange(new_range...)
        end
        # Get the range control
        rc = ui.state.range_control[]
        # Update the range of the corresponding slider
        slider = ui.main_menu.coord_sliders.sliders[prop_name]
        current_index = slider.value[]
        current_value = getproperty(rc, property)[current_index]
        slider.value[] = 1

        # Update the range control
        setproperty!(rc, property, new_range)

        # Get the updated range (after setting the property)
        new_range = getproperty(rc, property)

        # Update the slider range
        slider.range[] = 1:length(new_range)

        # Restore the slider value to the closest value
        closest_index = argmin(abs.(new_range .- current_value))
        set_close_to!(slider, closest_index)

        update_switch[] = old_update
    catch e
        # Re-enable Updates
        update_switch[] = old_update
        throw(e)
    end
    nothing
end

# ===========================================
#  Utility Functions to change UI elements
# ===========================================
function select_menu_option!(menu:: Menu, selection::String)::Nothing
    avail_opt = menu.options[]
    if !(selection in avail_opt)
        throw(ArgumentError("Selection '$selection' not in available options: $avail_opt"))
    end
    menu.i_selected[] = findfirst(==(selection), menu.options[])
    nothing
end

function select_variable!(ui::UIElements, var_name::String)::Nothing
    var_menu = ui.main_menu.variable_menu
    select_menu_option!(var_menu, var_name)
end

function select_plot_type!(ui::UIElements, plot_type::String)::Nothing
    plot_menu = ui.main_menu.plot_menu.plot_type
    select_menu_option!(plot_menu, plot_type)
end

function select_x_axis!(ui::UIElements, dim_name::String)::Nothing
    x_menu = ui.main_menu.coord_menu.menus[1]
    select_menu_option!(x_menu, dim_name)
    sync_dim_selections!(ui.state, ui.main_menu.coord_menu)
end

function select_y_axis!(ui::UIElements, dim_name::String)::Nothing
    y_menu = ui.main_menu.coord_menu.menus[2]
    select_menu_option!(y_menu, dim_name)
    sync_dim_selections!(ui.state, ui.main_menu.coord_menu)
end

function select_z_axis!(ui::UIElements, dim_name::String)::Nothing
    z_menu = ui.main_menu.coord_menu.menus[3]
    select_menu_option!(z_menu, dim_name)
    sync_dim_selections!(ui.state, ui.main_menu.coord_menu)
end


end # module