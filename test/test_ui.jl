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
    for opt in ["heatmap", "contour", "contourf", "surface", "wireframe", "line", "scatter", "volume", "contour3d"]
        @test opt in plot_menu.plot_type.options[]
    end
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

    dimensions = ["time", "depth", "level"]
    coord_menu = UI.init_coordinate_menu(fig, dimensions)

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

@testset "UI Main Menu" begin
    file = make_temp_dataset()
    dataset = Data.open_dataset(file)

    fig = Figure()

    main_menu = UI.init_main_menu(fig, dataset)

    # test types
    @test main_menu isa UI.MainMenu
    @test main_menu.variable_menu isa Menu
    @test main_menu.plot_menu isa UI.PlotMenu
    @test main_menu.coord_sliders isa SliderGrid
    @test main_menu.playback_menu isa UI.PlaybackMenu

    # test values
    @test length(main_menu.variable_menu.options[]) == length(dataset.variables)
    for dim in dataset.dimensions
        @test dim in [l.text[] for l in main_menu.coord_sliders.labels]
    end

    # test layout
    layout = UI.main_menu_layout(fig, main_menu)
    @test layout isa GridLayout
    @test layout.size == (6, 1)
end

@testset "UI Elements" begin
    file = make_temp_dataset()
    dataset = Data.open_dataset(file)

    fig = Figure()

    ui_elements = UI.init_ui_elements!(fig, dataset)

    # test types
    @test ui_elements isa UI.UIElements
    @test ui_elements.main_menu isa UI.MainMenu
    @test ui_elements.coord_menu isa UI.CoordinateMenu

    # test layout of the figure
    @test fig.layout.size == (2, 2)
end