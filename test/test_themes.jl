using Test
using Colors
using Makie
using CDFViewer.Constants
using CDFViewer.Themes

@testset "Themes.jl" begin

    # Every test in here installs a theme globally, and the files after
    # this one expect the default. Put it back whatever happens.
    function with_active_theme(f::Function)
        previous = Themes.active()
        try
            f()
        finally
            Themes.activate!(previous)
        end
    end

    @testset "Names" begin
        @testset "Every Makie theme is offered" begin
            @test Themes.theme_names() ==
                ["minimal", "light", "dark", "black", "ggplot2"]
            for name in Themes.theme_names()
                @test Themes.THEMES[name] isa Function
            end
        end

        @testset "Resolving a name" begin
            @test Themes.resolve("dark") == "dark"
            # Makie's own spelling, mixed case and stray whitespace
            @test Themes.resolve("theme_dark") == "dark"
            @test Themes.resolve("  ggPlot2 ") == "ggplot2"
            # the name of the look the viewer starts under
            @test Themes.resolve("default") == Themes.DEFAULT_THEME
            @test Themes.DEFAULT_THEME == "minimal"
        end

        @testset "Refusing a name" begin
            @test Themes.resolve("solarized") === nothing
            @test Themes.resolve("") === nothing
            message = Themes.unknown_theme_message("solarized")
            @test occursin("solarized", message)
            # the message names every theme there is, so the user can pick
            for name in Themes.theme_names()
                @test occursin(name, message)
            end
        end
    end

    @testset "Composition" begin
        @testset "Every theme carries the viewer's own sizes" begin
            for name in Themes.theme_names()
                theme = Themes.composed_theme(name)
                @test theme.Axis.xlabelsize[] == Constants.LABELSIZE
                @test theme.Axis3.zlabelsize[] == Constants.LABELSIZE
                @test theme.Axis.titlesize[] == Constants.TITLESIZE
                @test theme.Lines.inspectable[] == false
                # the LaTeX fonts are the app's, not the theme's
                @test theme.fonts.regular[] ==
                    Makie.theme_latexfonts().fonts.regular[]
            end
        end

        @testset "The default composes exactly as it always did" begin
            # what `create_figure` used to build by hand, key by key --
            # `Attributes` has no value equality to compare wholesale
            expected = merge(Makie.theme_latexfonts(), Makie.theme_minimal())
            expected = merge(expected, Themes.viewer_theme())
            composed = Themes.composed_theme(Themes.DEFAULT_THEME)
            # the widget layer is the only thing on top of it
            @test Set(setdiff(keys(composed), keys(expected))) ==
                Set([:Menu, :Button, :Toggle, :Slider])
            @test isempty(setdiff(keys(expected), keys(composed)))
            @test keys(composed.Axis) == keys(expected.Axis)
            for key in keys(composed.Axis)
                @test composed.Axis[key][] == expected.Axis[key][]
            end
            for key in keys(composed.Axis3)
                @test composed.Axis3[key][] == expected.Axis3[key][]
            end
            for key in (:regular, :bold, :italic, :bolditalic)
                @test composed.fonts[key][] == expected.fonts[key][]
            end
        end

        @testset "The composed theme derives what the installed one does" begin
            # `composed_theme` reads the colors off a theme that is not
            # installed yet, so the two derivations must not drift apart
            with_active_theme() do
                for name in Themes.theme_names()
                    composed = Themes.theme_colors(Themes.composed_theme(name))
                    Themes.activate!(name)
                    @test composed == Themes.theme_colors()
                end
            end
        end
    end

    # ============================================================
    #  The menu window's widgets
    # ============================================================

    @testset "Widget surfaces" begin
        # every attribute of a Block the menu window uses that names a
        # surface Makie fixes to a light gray or a black regardless of the
        # theme, paired with the value Makie itself gives it
        surface_attributes = [
            :Menu => [:selection_cell_color_inactive, :cell_color_inactive_even,
                      :cell_color_inactive_odd, :dropdown_arrow_color, :textcolor],
            :Button => [:buttoncolor, :labelcolor, :labelcolor_hover,
                        :labelcolor_active],
            :Toggle => [:framecolor_inactive],
            :Slider => [:color_inactive],
        ]

        makie_default(block::Symbol, key::Symbol) = Makie.to_color(
            Makie.default_attribute_values(getfield(Makie, block), nothing)[key])

        @testset "The default paints them exactly as Makie does" begin
            # every screenshot in the manual was taken under this theme
            with_active_theme() do
                Themes.activate!(Themes.DEFAULT_THEME)
                styled = Themes.block_theme(Themes.theme_colors())
                for (block, attrs) in surface_attributes, attr in attrs
                    @test Makie.to_color(styled[block][attr][]) ==
                        makie_default(block, attr)
                end
            end
        end

        @testset "Every theme states every one of them" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    styled = Themes.block_theme(Themes.theme_colors())
                    for (block, attrs) in surface_attributes
                        @test Set(attrs) ⊆ Set(keys(styled[block]))
                    end
                end
            end
        end

        @testset "And the list above is still all of them" begin
            # read back out of the Makie that is installed rather than
            # listed here a second time, so an attribute a later version
            # fixes to a color of its own fails this instead of quietly
            # staying light. A default naming a color literally is one
            # the theme cannot reach; `@inherit` already follows it, and
            # the accent pair is deliberately left where Makie put it
            names_own_color(expr::String) =
                !occursin("@inherit", expr) &&
                occursin(r"RGBf|:black\b|:white\b", expr)
            fixed(block::Symbol) = Set(
                key for (key, expr) in
                    Makie.attribute_default_expressions(getfield(Makie, block))
                if names_own_color(expr))

            for (block, attrs) in surface_attributes
                @test fixed(block) ⊆ Set(attrs)
            end
            # the two remaining Blocks the menu is built from fix nothing:
            # a `Label` inherits the theme's text color, and a `SliderGrid`
            # is only `Slider`s and `Label`s
            @test isempty(fixed(:Label))
            @test isempty(fixed(:SliderGrid))
        end

        @testset "A widget's face steps off its own theme's ground" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    colors = Themes.theme_colors()
                    ground = Themes.luminance(colors.background)
                    for face in (colors.widget_face, colors.menu_cell)
                        # away from the ground, but only just: a widget is
                        # a step off the page, not a block of ink on it
                        @test 0.01 < abs(Themes.luminance(face) - ground) < 0.15
                        # and away from it in the direction there is room
                        @test (Themes.luminance(face) > ground) ==
                            Themes.is_dark(colors.background)
                    end
                    # the dropdown row sits between the ground and the
                    # closed dropdown's own face
                    @test abs(Themes.luminance(colors.menu_cell) - ground) <
                        abs(Themes.luminance(colors.widget_face) - ground)
                end
            end
        end

        @testset "Lettering reads against the face under it" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    colors = Themes.theme_colors()
                    styled = Themes.block_theme(colors)
                    faces = [
                        styled.Menu.textcolor[] => colors.widget_face,
                        styled.Menu.textcolor[] => colors.menu_cell,
                        styled.Button.labelcolor[] => colors.widget_face,
                        styled.Button.labelcolor_hover[] => colors.accent_dimmed,
                        styled.Button.labelcolor_active[] => colors.accent,
                    ]
                    for (label, face) in faces
                        # theme_dark writes gray45 on gray10 and is a
                        # low-contrast look by choice, so the bar is what
                        # it asks for and not an absolute
                        @test abs(Themes.luminance(Makie.to_color(label)) -
                                  Themes.luminance(face)) > 0.25
                    end
                end
            end
        end

        @testset "The accent pair is left where Makie put it" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    styled = Themes.block_theme(Themes.theme_colors())
                    # what a widget lights up in is the same under every
                    # theme, which is what lets the sliders read it out of
                    # `Constants` and still agree with their neighbours
                    for (block, key) in ((:Menu, :cell_color_hover),
                                         (:Menu, :cell_color_active),
                                         (:Button, :buttoncolor_hover),
                                         (:Button, :buttoncolor_active),
                                         (:Toggle, :buttoncolor),
                                         (:Toggle, :framecolor_active),
                                         (:Slider, :color_active),
                                         (:Slider, :color_active_dimmed))
                        @test !haskey(styled[block], key)
                    end
                end
            end
        end
    end

    @testset "Installing" begin
        @testset "activate! installs and remembers" begin
            with_active_theme() do
                Themes.activate!("black")
                @test Themes.active() == "black"
                @test Makie.to_value(Makie.theme(:backgroundcolor)) == :black
                @test Makie.to_value(Makie.theme(:textcolor)) == :white
                Themes.activate!("minimal")
                @test Themes.active() == "minimal"
                # theme_minimal names neither, so Makie's own defaults show
                @test Makie.to_value(Makie.theme(:backgroundcolor)) == :white
                @test Makie.to_value(Makie.theme(:textcolor)) == :black
            end
        end

        @testset "activate! refuses a name it cannot install" begin
            with_active_theme() do
                @test_throws ArgumentError Themes.activate!("solarized")
                # and it is refused before anything is installed
                @test Themes.active() == Themes.DEFAULT_THEME
            end
        end
    end

    @testset "Derived colors" begin
        @testset "The default pair is what was hardcoded before" begin
            with_active_theme() do
                Themes.activate!(Themes.DEFAULT_THEME)
                colors = Themes.theme_colors()
                @test colors.background == Makie.to_color(:white)
                @test colors.text == Makie.to_color(:black)
                # land used to be :lightgray, an idle slider bar
                # rgb(240, 240, 240), and a grayed-out label :lightgray
                @test colors.land ≈ Makie.to_color(:lightgray) atol = 1e-6
                @test colors.inactive_text ≈ Makie.to_color(:lightgray) atol = 1e-6
                @test colors.inactive_slider_bar ≈
                    Makie.to_color(parse(Colorant, "rgb(240, 240, 240)")) atol = 1e-6
                # and the widget surfaces are Makie's own, to the bit
                @test colors.widget_face == Makie.to_color(RGBf(0.94, 0.94, 0.94))
                @test colors.menu_cell == Makie.to_color(RGBf(0.97, 0.97, 0.97))
                @test colors.dropdown_arrow == Makie.to_color((:black, 0.2))
            end
        end

        @testset "A dark ground turns the chrome round" begin
            with_active_theme() do
                Themes.activate!("black")
                colors = Themes.theme_colors()
                @test colors.background == Makie.to_color(:black)
                @test colors.text == Makie.to_color(:white)
                # every blend sits between the two, nearer the ground
                for blended in (colors.land, colors.inactive_text,
                                colors.inactive_slider_bar, colors.widget_face,
                                colors.menu_cell)
                    @test 0 < blended.r < 0.5
                    @test blended.alpha == 1
                end
                # and the land fill is the same distance from the ground as
                # it is under the default theme, just the other way round
                @test colors.land.r ≈ 1 - Makie.to_color(:lightgray).r atol = 1e-6
                # so is every widget surface, and the dropdown arrow has
                # turned from black to white
                @test colors.widget_face.r ≈ 1 - 0.94 atol = 1e-6
                @test colors.menu_cell.r ≈ 1 - 0.97 atol = 1e-6
                @test colors.dropdown_arrow == Makie.to_color((:white, 0.2))
            end
        end

        @testset "The starting colormap follows the ground" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    colors = Themes.theme_colors()
                    # a white-centred colormap on a light page, a
                    # dark-centred one on a dark page
                    @test colors.colormap == (Themes.is_dark(colors.background) ?
                                              Constants.DARK_COLORMAP :
                                              Constants.COLORMAP)
                    # and it is a colormap Makie can resolve
                    @test length(Makie.to_colormap(colors.colormap)) > 1
                end
                Themes.activate!(Themes.DEFAULT_THEME)
                @test Themes.theme_colors().colormap == :balance
                Themes.activate!("dark")
                @test Themes.theme_colors().colormap == :berlin
                Themes.activate!("black")
                @test Themes.theme_colors().colormap == :berlin
                Themes.activate!("light")
                @test Themes.theme_colors().colormap == :balance
                Themes.activate!("ggplot2")
                @test Themes.theme_colors().colormap == :balance
            end
        end

        @testset "The accent is Makie's own under every theme" begin
            with_active_theme() do
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    colors = Themes.theme_colors()
                    @test colors.accent == Makie.to_color(Constants.ACCENT_COLOR)
                    @test colors.accent_dimmed ==
                        Makie.to_color(Constants.ACCENT_DIMMED_COLOR)
                end
            end
        end

        @testset "ggplot2 names neither color and falls back" begin
            with_active_theme() do
                # theme_ggplot2 styles the axis only, so the chrome reads
                # Makie's own black-on-white pair rather than nothing
                Themes.activate!("ggplot2")
                colors = Themes.theme_colors()
                @test colors.background == Makie.to_color(:white)
                @test colors.text == Makie.to_color(:black)
            end
        end
    end

    @testset "Helpers" begin
        @testset "blend" begin
            white = Makie.to_color(:white)
            black = Makie.to_color(:black)
            @test Themes.blend(white, black, 0.0) == white
            @test Themes.blend(white, black, 1.0) == black
            @test Themes.blend(white, black, 0.5).r ≈ 0.5
            # the ground's opacity carries through
            @test Themes.blend(white, black, 0.5).alpha == 1
        end

        @testset "with_alpha" begin
            faded = Themes.with_alpha(Makie.to_color(:red), 0.25)
            @test faded.alpha == 0.25f0
            @test (faded.r, faded.g, faded.b) == (1.0f0, 0.0f0, 0.0f0)
        end

        @testset "readable_on" begin
            with_active_theme() do
                light = Makie.to_color(:white)
                dark = Makie.to_color(:black)
                Themes.activate!(Themes.DEFAULT_THEME)
                @test Themes.readable_on(light) == dark
                @test Themes.readable_on(dark) == light
                # it stays inside the theme's own pair, whichever way
                # round the two of them are
                Themes.activate!("black")
                @test Themes.readable_on(light) == Makie.to_color(:black)
                @test Themes.readable_on(dark) == Makie.to_color(:white)
            end
        end

        @testset "contrast_pole" begin
            @test Themes.contrast_pole(Makie.to_color(:black)) ==
                Makie.to_color(:white)
            @test Themes.contrast_pole(Makie.to_color(:white)) ==
                Makie.to_color(:black)
            # the accent pair splits either side of the middle, which is
            # what makes Makie's fixed hover and active labels come out
            @test Themes.contrast_pole(Makie.to_color(Constants.ACCENT_COLOR)) ==
                Makie.to_color(:white)
            @test Themes.contrast_pole(
                Makie.to_color(Constants.ACCENT_DIMMED_COLOR)) ==
                Makie.to_color(:black)
        end

        @testset "is_dark" begin
            @test Themes.is_dark(Makie.to_color(:black))
            @test Themes.is_dark(Makie.to_color(:gray10))
            @test !Themes.is_dark(Makie.to_color(:white))
            @test !Themes.is_dark(Makie.to_color(:gray92))
        end
    end
end
