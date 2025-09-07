module UI

using GLMakie

import ..Constants
import ..Data

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
        Menu(fig, options=["Info"]),
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
#  Coordinate Sliders
# ============================================
struct CoordinateSliders
    sliders::Dict{String, Slider}
    continuous_values::Dict{String, Observable{Float64}}
    labels::Dict{String, Label}
    valuelabels::Dict{String, Label}
    slider_grid::SliderGrid
    fig::Figure
end

function CoordinateSliders(fig::Figure, dataset::Data.CDFDataset)::CoordinateSliders
    coord_sliders = SliderGrid(fig,[
        (label=dim, range=1:dataset.ds.dim[dim], startvalue=1, update_while_dragging=false)
        for dim in dataset.dimensions]...)
    labels = Dict(
        dim => coord_sliders.labels[i] for (i, dim) in enumerate(dataset.dimensions))
    sliders = Dict(
        dim => coord_sliders.sliders[i] for (i, dim) in enumerate(dataset.dimensions))
    valuelabels = Dict(
        dim => coord_sliders.valuelabels[i] for (i, dim) in enumerate(dataset.dimensions))

    continuous_slider = Dict(key => @lift(float.($(val.value))) for (key, val) in sliders)
    for key in keys(sliders)
        on(continuous_slider[key]) do v
            set_close_to!(sliders[key], v)
        end
    end

    CoordinateSliders(sliders, continuous_slider, labels, valuelabels, coord_sliders, fig)
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
                    options = [Constants.NOT_SELECTED_LABEL; dataset.dimensions],
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
    coord_sliders.continuous_values[dim][] = new_value
    nothing
end

# ============================================
#  Main Menu
# ============================================

struct MainMenu
    variable_menu::Menu
    plot_menu::PlotMenu
    playback_menu::PlaybackMenu
    coord_sliders::CoordinateSliders
    fig::Figure
end

function MainMenu(fig::Figure, dataset::Data.CDFDataset)::MainMenu
    variable_menu = Menu(fig, options = dataset.variables)
    plot_menu = PlotMenu(fig)
    coord_sliders = CoordinateSliders(fig, dataset)
    playback_menu = PlaybackMenu(fig, dataset, coord_sliders.sliders)
    MainMenu(variable_menu, plot_menu, playback_menu, coord_sliders, fig)
end

function layout(main_menu::MainMenu)::GridLayout
    vgrid!(
        Label(main_menu.fig, L"\textbf{CDF Viewer}", halign = :center, fontsize=30, tellwidth=false),
        hgrid!(Label(main_menu.fig, L"\textbf{Variable}", width = nothing), main_menu.variable_menu),
        layout(main_menu.plot_menu),
        layout(main_menu.playback_menu),
        Label(main_menu.fig, L"\textbf{Coordinates}", width = nothing),
        main_menu.coord_sliders.slider_grid,
    )
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
#  All Variables Controlled By the UI
# ============================================

struct State
    variable::Observable{String}
    plot_type_name::Observable{String}
    x_name::Observable{String}
    y_name::Observable{String}
    z_name::Observable{String}
    dim_obs::Observable{Dict{String, Int}}
    plot_kw::Observable{Union{String, Nothing}}
end

function State(main_menu::MainMenu, coord_menu::CoordinateMenu)::State
    # Create an observable dictionary that tracks the values of all sliders
    slider_values = Dict(dim => slider.value for (dim, slider) in main_menu.coord_sliders.sliders)
    dim_obs = Observable(Dict(dim => value[] for (dim, value) in slider_values))

    # Set up listeners to update the dictionary when any slider changes
    for (dim, value_obs) in slider_values
        on(value_obs) do v
            dim_obs[][dim] = v
            notify(dim_obs)
        end
    end

    State(
        Observable(main_menu.variable_menu.selection[]),
        Observable(main_menu.plot_menu.plot_type.selection[]),
        Observable(coord_menu.menus[1].selection[]),
        Observable(coord_menu.menus[2].selection[]),
        Observable(coord_menu.menus[3].selection[]),
        dim_obs,
        main_menu.plot_menu.plot_kw.stored_string,
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
    coord_menu::CoordinateMenu
    state::State
    fig::Figure
end

function UIElements(fig::Figure, dataset::Data.CDFDataset)::UIElements
    # Initialize the menus
    main_menu = MainMenu(fig, dataset)
    coord_menu = CoordinateMenu(fig)
    # Initialize the UI state
    state = State(main_menu, coord_menu)
    # Put the menus in the figure
    fig[1:2, 1] = layout(main_menu)
    fig[2, 2] = layout(coord_menu)
    # Return the UI elements
    UIElements(main_menu, coord_menu, state, fig)
end

end # module