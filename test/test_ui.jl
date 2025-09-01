using Test
using CDFViewer.Data
using CDFViewer.UI
using GLMakie

@testset "UI Plot Menu" begin
    fig = Figure()
    @test fig isa Figure

    plot_menu = UI.init_plot_menu(fig)

    # test types
    @test plot_menu isa UI.PlotMenu
    @test plot_menu.plot_type isa Menu
    @test plot_menu.axes_kw isa Textbox
    @test plot_menu.plot_kw isa Textbox

    # test values
    @test plot_menu.plot_type.options[] == ["Info"]
    @test plot_menu.axes_kw.placeholder[] == "e.g., xscale=log10; yscale=log10"
    @test plot_menu.plot_kw.placeholder[] == "e.g., colormap=:viridis; colorrange=(-1,1)"

    # test layout
    layout = UI.plot_menu_layout(fig, plot_menu)
    @test layout isa GridLayout
    @test layout.size == (3, 1)
    sublayout1 = layout.content[1].content
    @test sublayout1 isa GridLayout
    @test sublayout1.size == (1, 2)

end

@testset "UI Playback Menu" begin
    fig = Figure()

    dimensions = ["time", "depth", "level"]
    playback_menu = UI.init_playback_menu(fig, dimensions)

    # test types
    @test playback_menu isa UI.PlaybackMenu
    @test playback_menu.toggle isa Toggle
    @test playback_menu.speed isa Slider
    @test playback_menu.var isa Menu

    # test values
    @test playback_menu.toggle.active[] == false
    @test playback_menu.speed.value[] == 1.0
    for opt in dimensions
        @test opt in playback_menu.var.options[]
    end

    # test layout
    layout = UI.playback_menu_layout(fig, playback_menu)
    @test layout isa GridLayout
    @test layout.size == (1, 4)

end

@testset "UI Coordinate Menu" begin
    fig = Figure()

    coord_menu = UI.init_coordinate_menu(fig)

    # test types
    @test coord_menu isa UI.CoordinateMenu
    @test coord_menu.labels isa Vector{Label}
    @test coord_menu.menus isa Vector{Menu}

    # test values
    @test length(coord_menu.labels) == 3
    @test length(coord_menu.menus) == 3

    # test layout
    layout = UI.coordinate_menu_layout(coord_menu)
    @test layout isa GridLayout
    @test layout.size == (1, 3)
    for sublayout in layout.content
        @test sublayout.content isa GridLayout
        @test sublayout.content.size == (1, 2)
    end
end

@testset "UI Coordinate Sliders" begin
    dataset = make_temp_dataset()

    fig = Figure()
    coord_sliders = UI.init_coordinate_sliders(fig, dataset)

    # test types
    @test coord_sliders isa UI.CoordinateSliders
    @test coord_sliders.labels isa Dict{String, Label}
    @test coord_sliders.sliders isa Dict{String, Slider}
    @test coord_sliders.slider_grid isa SliderGrid

    # test values
    @test length(coord_sliders.labels) == length(dataset.dimensions)
    @test length(coord_sliders.sliders) == length(dataset.dimensions)
end

@testset "UI Main Menu" begin
    dataset = make_temp_dataset()

    fig = Figure()

    main_menu = UI.init_main_menu(fig, dataset)

    # test types
    @test main_menu isa UI.MainMenu
    @test main_menu.variable_menu isa Menu
    @test main_menu.plot_menu isa UI.PlotMenu
    @test main_menu.coord_sliders isa UI.CoordinateSliders
    @test main_menu.playback_menu isa UI.PlaybackMenu

    # test layout
    layout = UI.main_menu_layout(fig, main_menu)
    @test layout isa GridLayout
    @test layout.size == (6, 1)
end

@testset "UI State" begin
    dataset = make_temp_dataset()
    fig = Figure()

    main_menu = UI.init_main_menu(fig, dataset)
    coord_menu = UI.init_coordinate_menu(fig)
    ui_state = UI.init_state(main_menu, coord_menu)

    # test types
    @test ui_state isa UI.State
    @test ui_state.variable isa Observable{String}
    @test ui_state.plot_type_name isa Observable{String}
    @test ui_state.x_name isa Observable{String}
    @test ui_state.y_name isa Observable{String}
    @test ui_state.z_name isa Observable{String}
    @test ui_state.dim_obs isa Observable{Dict{String, Int}}

    # test values
    @test ui_state.variable[] == "1d_float"
    @test ui_state.plot_type_name[] == "Info"
    @test ui_state.x_name[] == "Not Selected"
    @test ui_state.y_name[] == "Not Selected"
    @test ui_state.z_name[] == "Not Selected"
    for (dim, idx) in ui_state.dim_obs[]
        @test dim in dataset.dimensions
        @test idx == 1
    end

    # create a counter to check that dim_obs is updated
    counter = Observable(0)
    on(ui_state.dim_obs) do _
        counter[] += 1
    end

    # change some values and check that dim_obs is updated
    main_menu.coord_sliders.sliders["lon"].value[] = 3
    @test ui_state.dim_obs[]["lon"] == 3
    @test counter[] == 1

    # change the selection of the variable menu and
    main_menu.variable_menu.i_selected[] = 3
    @test main_menu.variable_menu.selection[] == "3d_float"
    # the variable observable should not be updated here
    @test ui_state.variable[] == "1d_float"

    # change the selection of the the selected coordinate
    for (i, name) in enumerate([ui_state.x_name, ui_state.y_name, ui_state.z_name])
        coord_menu.menus[i].options[] = ["Not Selected"; dataset.dimensions]
        coord_menu.menus[i].i_selected[] = i + 1
        @test name[] == dataset.dimensions[i]
    end
end

@testset "UI Elements" begin
    dataset = make_temp_dataset()

    fig = Figure()

    ui_elements = UI.init_ui_elements!(fig, dataset)

    # test types
    @test ui_elements isa UI.UIElements
    @test ui_elements.main_menu isa UI.MainMenu
    @test ui_elements.coord_menu isa UI.CoordinateMenu

    # test layout of the figure
    @test fig.layout.size == (2, 2)
end