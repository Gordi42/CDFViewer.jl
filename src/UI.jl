module UI

using GLMakie

import ..Constants
import ..Data

# ============================================
#  Plot Menu
# ============================================

struct PlotMenu
    plot_type::Menu
    axes_kw::Textbox
    plot_kw::Textbox
    fig::Figure
end

# ------------------------------------
#  Constructor
# ------------------------------------

function PlotMenu(fig::Figure)
    function construct_textbox(placeholder::String)
        Textbox(
            fig,
            placeholder = placeholder,
            tellwidth = false,
            defocus_on_submit = false,
            halign = :left,
        )
    end

    PlotMenu(
        Menu(fig, options=["Info"]),
        construct_textbox(Constants.AXES_KW_HINTS),
        construct_textbox(Constants.PLOT_KW_HINTS),
        fig,
    )
end

# ------------------------------------
#  Methods
# -----------------------------------

function layout(plot_menu::PlotMenu)
    vgrid!(
        hgrid!(
            Label(plot_menu.fig, L"\textbf{Plot Settings}", width = nothing),
            plot_menu.plot_type),
        plot_menu.axes_kw,
        plot_menu.plot_kw,
    )
end

# ============================================
#  Coordinate Sliders
# ============================================
struct CoordinateSliders
    sliders::Dict{String, Slider}
    labels::Dict{String, Label}
    valuelabels::Dict{String, Label}
    slider_grid::SliderGrid
end

# ------------------------------------
#  Constructor
# ------------------------------------

function CoordinateSliders(fig::Figure, dataset::Data.CDFDataset)
    coord_sliders = SliderGrid(fig,[
        (label=dim, range=1:dataset.ds.dim[dim], startvalue=1, update_while_dragging=false)
        for dim in dataset.dimensions]...)
    labels = Dict(
        dim => coord_sliders.labels[i] for (i, dim) in enumerate(dataset.dimensions))
    sliders = Dict(
        dim => coord_sliders.sliders[i] for (i, dim) in enumerate(dataset.dimensions))
    valuelabels = Dict(
        dim => coord_sliders.valuelabels[i] for (i, dim) in enumerate(dataset.dimensions))
    CoordinateSliders(sliders, labels, valuelabels, coord_sliders)
end

# ============================================
#  Playback Menu
# ============================================

struct PlaybackMenu
    toggle::Toggle
    speed::Slider
    var::Menu
    label::Label
end

function create_playback_label(
    fig::Figure,
    dataset::Data.CDFDataset,
    vmenu::Menu,
    coord_sliders::Dict{String, Slider},
    )
    label = Label(fig, Constants.NO_DIM_SELECTED_LABEL, halign = :left, tellwidth = false)
    slider_values = [slider.value for slider in values(coord_sliders)]

    for trigger in (vmenu.selection, slider_values...)
        on(trigger) do _
            dim = vmenu.selection[]
            if dim == Constants.NOT_SELECTED_LABEL
                label.text[] = Constants.NO_DIM_SELECTED_LABEL
            else
                idx = coord_sliders[dim].value[]
                label.text[] = Data.get_dim_value_label(dataset, dim, idx)
            end
        end
    end
    notify(vmenu.selection)
    label
end

function init_playback_menu(fig::Figure, dataset::Data.CDFDataset, coord_sliders::Dict{String, Slider})
    toggle = Toggle(fig, active = false)
    speed_slider = Slider(fig, range = 0.1:0.1:10.0, startvalue = 1.0)
    var_menu = Menu(fig,
                    options = [Constants.NOT_SELECTED_LABEL; dataset.dimensions],
                    tellwidth = false)
    label = create_playback_label(fig, dataset, var_menu, coord_sliders)
    PlaybackMenu(toggle, speed_slider, var_menu, label)
end

function playback_menu_layout(fig::Figure, playback_menu::PlaybackMenu)
    vgrid!(
        hgrid!(
            Label(fig, L"\textbf{Play}", width = 30), 
            playback_menu.toggle,
            playback_menu.speed,
            playback_menu.var,
        ),
        playback_menu.label,
    )
end

# ============================================
#  Main Menu
# ============================================

struct MainMenu
    variable_menu::Menu
    plot_menu::PlotMenu
    playback_menu::PlaybackMenu
    coord_sliders::CoordinateSliders
end

function init_main_menu(fig::Figure, dataset::Data.CDFDataset)
    variable_menu = Menu(fig, options = dataset.variables)
    plot_menu = PlotMenu(fig)
    coord_sliders = CoordinateSliders(fig, dataset)
    playback_menu = init_playback_menu(fig, dataset, coord_sliders.sliders)
    MainMenu(variable_menu, plot_menu, playback_menu, coord_sliders)
end

function main_menu_layout(fig::Figure, main_menu::MainMenu)
    vgrid!(
        Label(fig, L"\textbf{CDF Viewer}", halign = :center, fontsize=30, tellwidth=false),
        hgrid!(Label(fig, L"\textbf{Variable}", width = nothing), main_menu.variable_menu),
        layout(main_menu.plot_menu),
        playback_menu_layout(fig, main_menu.playback_menu),
        Label(fig, L"\textbf{Coordinates}", width = nothing),
        main_menu.coord_sliders.slider_grid,
    )
end

# ============================================
#  Coordinate Menu
# ============================================

struct CoordinateMenu
    labels::Vector{Label}
    menus::Vector{Menu}
end

function init_coordinate_menu(fig::Figure)
    dimension_selections = [
        Menu(fig, options = [Constants.NOT_SELECTED_LABEL], tellwidth = false)
        for i in 1:3
    ]
    dimension_labels = [Label(fig, label) for label in Constants.DIMENSION_LABELS]
    CoordinateMenu(dimension_labels, dimension_selections)
end

function coordinate_menu_layout(coord_menu::CoordinateMenu)
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
    axes_kw::Observable{Union{String, Nothing}}
    plot_kw::Observable{Union{String, Nothing}}
end

function create_dimension_selection(coord_sliders::CoordinateSliders)
    slider_values = Dict(dim => slider.value for (dim, slider) in coord_sliders.sliders)
    dim_obs = Observable(Dict(dim => value[] for (dim, value) in slider_values))

    for (dim, value_obs) in slider_values
        on(value_obs) do v
            dim_obs[][dim] = v
            notify(dim_obs)
        end
    end

    dim_obs
end

function init_state(main_menu::MainMenu, coord_menu::CoordinateMenu)
    State(
        Observable(main_menu.variable_menu.selection[]),
        Observable(main_menu.plot_menu.plot_type.selection[]),
        Observable(coord_menu.menus[1].selection[]),
        Observable(coord_menu.menus[2].selection[]),
        Observable(coord_menu.menus[3].selection[]),
        create_dimension_selection(main_menu.coord_sliders),
        main_menu.plot_menu.axes_kw.stored_string,
        main_menu.plot_menu.plot_kw.stored_string,
    )
end

function sync_dim_selections!(state::State, coord_menu::CoordinateMenu)
    state.x_name[] = coord_menu.menus[1].selection[]
    state.y_name[] = coord_menu.menus[2].selection[]
    state.z_name[] = coord_menu.menus[3].selection[]
end

# ============================================
#  All UI Elements
# ============================================

struct UIElements
    main_menu::MainMenu
    coord_menu::CoordinateMenu
    state::State
end

function init_ui_elements!(fig::Figure, dataset::Data.CDFDataset)
    # Initialize the menus
    main_menu = init_main_menu(fig, dataset)
    coord_menu = init_coordinate_menu(fig)
    # Initialize the UI state
    state = init_state(main_menu, coord_menu)
    # Put the menus in the figure
    fig[1:2, 1] = main_menu_layout(fig, main_menu)
    fig[2, 2] = coordinate_menu_layout(coord_menu)
    # Return the UI elements
    UIElements(main_menu, coord_menu, state)
end

end # module