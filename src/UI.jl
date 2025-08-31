module UI

using GLMakie

import ..Data: CDFDataset

# ============================================
#  Plot Menu
# ============================================

struct PlotMenu
    plot_type::Menu
    axes_kw::Textbox
    plot_kw::Textbox
end

function construct_textbox(fig::Figure, placeholder::String)
    Textbox(
        fig,
        placeholder = placeholder,
        tellwidth = false,
        defocus_on_submit = false,
        halign = :left,
    )
end

function init_plot_menu(fig::Figure)
    plot_type_menu = Menu(fig, options=["Info"])
    axes_kw_box = construct_textbox(fig, "e.g., xscale=log10; yscale=log10")
    plot_kw_box = construct_textbox(fig, "e.g., colormap=:viridis; colorrange=(-1,1)")
    PlotMenu(plot_type_menu, axes_kw_box, plot_kw_box)
end

function plot_menu_layout(fig::Figure, plot_menu::PlotMenu)
    vgrid!(
        hgrid!(
            Label(fig, L"\textbf{Plot Settings}", width = nothing),
            plot_menu.plot_type),
        plot_menu.axes_kw,
        plot_menu.plot_kw,
    )
end

# ============================================
#  Playback Menu
# ============================================

struct PlaybackMenu
    toggle::Toggle
    speed::Slider
    var::Menu
end

function init_playback_menu(fig::Figure, dimensions)
    toggle = Toggle(fig, active = false)
    speed_slider = Slider(fig, range = 0.1:0.1:10.0, startvalue = 1.0)
    var_menu = Menu(fig, options = dimensions, tellwidth = false)
    PlaybackMenu(toggle, speed_slider, var_menu)
end

function playback_menu_layout(fig::Figure, playback_menu::PlaybackMenu)
    hgrid!(
        Label(fig, L"\textbf{Play}", width = 30), 
        playback_menu.toggle,
        playback_menu.speed,
        playback_menu.var,
    )
end

# ============================================
#  Main Menu
# ============================================

struct MainMenu
    variable_menu::Menu
    plot_menu::PlotMenu
    coord_sliders::SliderGrid
    playback_menu::PlaybackMenu
end

function init_main_menu(fig::Figure, dataset::CDFDataset)
    variable_menu = Menu(fig, options = dataset.variables)
    plot_menu = init_plot_menu(fig)
    coord_sliders = SliderGrid(fig,[
            (label=dim, range=1:dataset.ds.dim[dim], startvalue=1, update_while_dragging=false)
            for dim in dataset.dimensions]...)
    playback_menu = init_playback_menu(fig, dataset.dimensions)
    MainMenu(variable_menu, plot_menu, coord_sliders, playback_menu)
end

function main_menu_layout(fig::Figure, main_menu::MainMenu)
    vgrid!(
        Label(fig, L"\textbf{CDF Viewer}", halign = :center, fontsize=30, tellwidth=false),
        hgrid!(Label(fig, L"\textbf{Variable}", width = nothing), main_menu.variable_menu),
        plot_menu_layout(fig, main_menu.plot_menu),
        Label(fig, L"\textbf{Coordinates}", width = nothing),
        main_menu.coord_sliders,
        playback_menu_layout(fig, main_menu.playback_menu)
    )
end

# ============================================
#  Coordinate Menu
# ============================================

struct CoordinateMenu
    labels::Vector{Label}
    menus::Vector{Menu}
end

function init_coordinate_menu(fig::Figure, dimensions)
    dimension_selections = [
        Menu(fig, options = dimensions, tellwidth = false)
        for i in 1:3
    ]
    dimension_labels = [
        Label(fig, label)
        for label in ("X Variable", "Y Variable", "Z Variable")
    ]
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
end

function init_state(main_menu::MainMenu, coord_menu::CoordinateMenu)
    State(
        main_menu.variable_menu.selection,
        main_menu.plot_menu.plot_type.selection,
        coord_menu.menus[1].selection,
        coord_menu.menus[2].selection,
        coord_menu.menus[3].selection,
    )
end


# ============================================
#  All UI Elements
# ============================================

struct UIElements
    main_menu::MainMenu
    coord_menu::CoordinateMenu
    state::State
end

function init_ui_elements!(fig::Figure, dataset::CDFDataset)
    # Initialize the menus
    main_menu = init_main_menu(fig, dataset)
    coord_menu = init_coordinate_menu(fig, dataset.dimensions)
    # Initialize the UI state
    state = init_state(main_menu, coord_menu)
    # Put the menus in the figure
    fig[1:2, 1] = main_menu_layout(fig, main_menu)
    fig[2, 2] = coordinate_menu_layout(coord_menu)
    # Return the UI elements
    UIElements(main_menu, coord_menu, state)
end

end # module