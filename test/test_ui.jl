using Test
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using GLMakie

@testset "UI.jl" begin

    # ============================================
    #  Plot Menu
    # ============================================

    @testset "Plot Menu" begin

        @testset "Types" begin
            # Arange
            plot_menu = UI.PlotMenu(Figure())

            # Assert
            @test plot_menu isa UI.PlotMenu
            @test plot_menu.plot_type isa Menu
            @test plot_menu.plot_kw isa Textbox
        end

        @testset "Values" begin
            # Arange
            plot_menu = UI.PlotMenu(Figure())

            # Assert
            @test plot_menu.plot_type.options[] == ["Info"]
            @test plot_menu.plot_kw.placeholder[] == Constants.PLOT_KW_HINTS
        end

        @testset "Layout" begin
            # Arange
            fig = Figure()
            plot_menu = UI.PlotMenu(fig)

            # Act
            layout = UI.layout(plot_menu)

            # Assert
            @test layout isa GridLayout
            @test layout.size == (2, 1)
            sublayout1 = layout.content[1].content
            @test sublayout1 isa GridLayout
            @test sublayout1.size == (1, 2)
        end
    end

    # ============================================
    #  Coordinate Sliders
    # ============================================

    @testset "UI Coordinate Sliders" begin
        @testset "Types" begin
            # Arange
            coord_sliders = UI.CoordinateSliders(Figure(), make_temp_dataset())

            # Assert
            @test coord_sliders isa UI.CoordinateSliders
            @test coord_sliders.continuous_values isa Dict{String, Observable{Float64}}
            @test coord_sliders.labels isa Dict{String, Label}
            @test coord_sliders.sliders isa Dict{String, Slider}
            @test coord_sliders.slider_grid isa SliderGrid
        end

        @testset "Values" begin
            # Arange
            dataset = make_temp_dataset()
            coord_sliders = UI.CoordinateSliders(Figure(), dataset)

            # Assert
            @test length(coord_sliders.labels) == length(dataset.dimensions)
            @test length(coord_sliders.sliders) == length(dataset.dimensions)
            @test length(coord_sliders.valuelabels) == length(dataset.dimensions)
            @test length(coord_sliders.continuous_values) == length(dataset.dimensions)
        end

        @testset "Slider Continuity" begin
            # Arange
            dataset = make_temp_dataset()
            coord_sliders = UI.CoordinateSliders(Figure(), dataset)
            sliders = coord_sliders.sliders
            cont = coord_sliders.continuous_values

            # Act: Set the slider
            set_close_to!(sliders["lon"], 3.0)
            
            # Assert: The continuous value should be adjusted
            @test cont["lon"][] == sliders["lon"].value[]

            # Act: Set the continuous value
            cont["lon"][] = 3.8

            # Assert: The slider value should be adjusted
            @test sliders["lon"].value[] == 4
        end
    end

    # ============================================
    #  Playback Menu
    # ============================================

    @testset "UI Playback Menu" begin
        function init_playback_menu(fig::Figure=Figure())
            dataset = make_temp_dataset()
            coord_sliders = UI.CoordinateSliders(fig, dataset)

            UI.PlaybackMenu(fig, dataset, coord_sliders.sliders)
        end

        @testset "Types" begin
            # Arange
            playback_menu = init_playback_menu()

            # Assert
            @test playback_menu isa UI.PlaybackMenu
            @test playback_menu.toggle isa Toggle
            @test playback_menu.speed isa Slider
            @test playback_menu.var isa Menu
            @test playback_menu.label isa Label
        end

        @testset "Values" begin
            # Arange
            playback_menu = init_playback_menu()

            # Assert
            @test playback_menu.toggle.active[] == false
            @test playback_menu.speed.value[] == 1.0
            @test playback_menu.label.text[] == Constants.NO_DIM_SELECTED_LABEL
            for opt in keys(DIM_DICT)
                @test opt in playback_menu.var.options[]
            end
        end

        @testset "Layout" begin
            # Arange
            fig = Figure()
            playback_menu = init_playback_menu(fig)

            # Act
            layout = UI.layout(playback_menu)

            # Assert
            @test layout isa GridLayout
            @test layout.size == (2, 1)
            sublayout1 = layout.content[1].content
            @test sublayout1 isa GridLayout
            @test sublayout1.size == (1, 4)
        end

        @testset "Playback Label" begin
            # Arange
            fig = Figure()
            dataset = make_temp_dataset()
            coord_sliders = UI.CoordinateSliders(fig, dataset)
            playback_menu = UI.PlaybackMenu(fig, dataset, coord_sliders.sliders)

            # Act
            playback_menu.var.i_selected[] = findfirst(==("string_dim"), playback_menu.var.options[])
            coord_sliders.sliders["string_dim"].value[] = 2

            # Assert
            @test playback_menu.label.text[] == "  → string_dim: " * dataset.ds["string_dim"][2]
        end
    end

    # ============================================
    #  Main Menu
    # ============================================

    @testset "UI Main Menu" begin
        function init_main_menu(fig::Figure=Figure())
            dataset = make_temp_dataset()
            UI.MainMenu(fig, dataset)
        end

        @testset "Types" begin
            # Arange
            main_menu = init_main_menu()

            # Assert
            @test main_menu isa UI.MainMenu
            @test main_menu.variable_menu isa Menu
            @test main_menu.plot_menu isa UI.PlotMenu
            @test main_menu.coord_sliders isa UI.CoordinateSliders
            @test main_menu.playback_menu isa UI.PlaybackMenu
        end

        @testset "Layout" begin
            # Arange
            fig = Figure()
            main_menu = init_main_menu(fig)

            # Act
            layout = UI.layout(main_menu)

            # Assert
            @test layout isa GridLayout
            @test layout.size == (6, 1)
        end
    end

    # ============================================
    #  Coordinate Menu
    # ============================================

    @testset "UI Coordinate Menu" begin
        @testset "Types" begin
            # Arange
            coord_menu = UI.CoordinateMenu(Figure())

            # Assert
            @test coord_menu isa UI.CoordinateMenu
            @test coord_menu.labels isa Vector{Label}
            @test coord_menu.menus isa Vector{Menu}
        end

        @testset "Values" begin
            # Arange
            coord_menu = UI.CoordinateMenu(Figure())

            # Assert
            @test length(coord_menu.labels) == 3
            @test length(coord_menu.menus) == 3
            for (i, label) in enumerate(Constants.DIMENSION_LABELS)
                @test coord_menu.labels[i].text[] == label
                @test coord_menu.menus[i].selection[] == Constants.NOT_SELECTED_LABEL
            end
        end

        @testset "Layout" begin
            # Arange
            coord_menu = UI.CoordinateMenu(Figure())
            layout = UI.layout(coord_menu)

            # Assert
            @test layout isa GridLayout
            @test layout.size == (1, 3)
            for sublayout in layout.content
                @test sublayout.content isa GridLayout
                @test sublayout.content.size == (1, 2)
            end
        end
    end

    # ============================================
    #  UI State
    # ============================================

    @testset "UI State" begin
        function init_state(fig::Figure=Figure(),
                            dataset::Data.CDFDataset=make_temp_dataset())
            main_menu = UI.MainMenu(fig, dataset)
            coord_menu = UI.CoordinateMenu(fig)
            UI.State(main_menu, coord_menu), main_menu, coord_menu
        end

        @testset "Types" begin
            # Arange
            state = init_state()[1]

            # Assert
            @test state isa UI.State
            @test state.variable isa Observable{String}
            @test state.plot_type_name isa Observable{String}
            @test state.x_name isa Observable{String}
            @test state.y_name isa Observable{String}
            @test state.z_name isa Observable{String}
            @test state.dim_obs isa Observable{Dict{String, Int}}
        end

        @testset "Values" begin
            # Arange
            dataset = make_temp_dataset()
            state = init_state(Figure(), dataset)[1]

            # Assert
            @test state.variable[] == "1d_float"
            @test state.plot_type_name[] == "Info"
            @test state.x_name[] == Constants.NOT_SELECTED_LABEL
            @test state.y_name[] == Constants.NOT_SELECTED_LABEL
            @test state.z_name[] == Constants.NOT_SELECTED_LABEL
            for (dim, idx) in state.dim_obs[]
                @test dim in dataset.dimensions
                @test idx == 1
            end
        end

        @testset "Dimension Selection" begin
            # Arange
            state, main_menu, coord_menu = init_state()
            # Create a counter to test if the observable triggers an event
            counter = Observable(0)
            on(state.dim_obs) do _
                counter[] += 1
            end

            # Act
            main_menu.coord_sliders.sliders["lon"].value[] = 3

            # Assert
            @test counter[] == 1
            @test state.dim_obs[]["lon"] == 3
        end

        @testset "Variable Selection" begin
            # Arange
            state, main_menu, coord_menu = init_state()
            
            # Act
            main_menu.variable_menu.i_selected[] = 3

            # Assert
            @test main_menu.variable_menu.selection[] == "3d_float"
            # the variable observable should not be updated here
            @test state.variable[] == "1d_float"
        end

        @testset "Coordinate Selection" begin
            # Arange
            dataset = make_temp_dataset()
            state, main_menu, coord_menu = init_state(Figure(), dataset)

            for (i, name) in enumerate([state.x_name, state.y_name, state.z_name])
                # Act
                coord_menu.menus[i].options[] = [Constants.NOT_SELECTED_LABEL; dataset.dimensions]
                coord_menu.menus[i].i_selected[] = i + 1

                # Assert
                # At first the xi_name observable should not be updated
                @test name[] == Constants.NOT_SELECTED_LABEL
                # after syncing the observable should be updated
                UI.sync_dim_selections!(state, coord_menu)
                @test name[] == dataset.dimensions[i]
            end
        end
    end

    # ============================================
    #  UI Elements
    # ============================================

    @testset "UI Elements" begin
        # Arange
        dataset = make_temp_dataset()
        fig = Figure()
        ui_elements = UI.UIElements(fig, dataset)

        # Assert types
        @test ui_elements isa UI.UIElements
        @test ui_elements.main_menu isa UI.MainMenu
        @test ui_elements.coord_menu isa UI.CoordinateMenu

        # Assert Layout
        @test fig.layout.size == (2, 2)
    end

end