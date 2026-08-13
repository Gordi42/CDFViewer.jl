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
            @test keys(composed) == keys(expected)
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
                                colors.inactive_slider_bar)
                    @test 0 < blended.r < 0.5
                    @test blended.alpha == 1
                end
                # and the land fill is the same distance from the ground as
                # it is under the default theme, just the other way round
                @test colors.land.r ≈ 1 - Makie.to_color(:lightgray).r atol = 1e-6
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
                # a button's face is light gray under every theme, so its
                # label is dark under every theme -- never white on white
                @test Themes.widget_label_color() == dark
                for name in Themes.theme_names()
                    Themes.activate!(name)
                    label = Themes.widget_label_color()
                    @test abs(Themes.luminance(label) -
                              Themes.luminance(Makie.to_color(
                                  Constants.WIDGET_FACE_COLOR))) > 0.4
                end
            end
        end
    end
end
