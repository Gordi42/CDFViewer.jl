using Test
using DataStructures
using GLMakie
using GeoMakie
using Suppressor
using CDFViewer.Constants
using CDFViewer.Plotting

@testset "Plotting.jl" begin

    # Arrange - helper function
    function init_figure_data()
        dataset = make_temp_dataset()
        ui = UI.UIElements(dataset)

        plot_data = Plotting.PlotData(ui.state, dataset)
        fig_data = Plotting.FigureData(plot_data, ui)
        (fig_data, ui.state, dataset)
    end

    function arrange_and_create_axis(var::String, sel::Vector{String}, plot_type::String)
        (fig_data, state, dataset) = init_figure_data()
        state.variable[] = var
        for (dim, name) in zip((state.x_name, state.y_name, state.z_name),
                (sel..., Constants.NOT_SELECTED_LABEL, Constants.NOT_SELECTED_LABEL))
            dim[] = name
        end
        state.plot_type_name[] = plot_type
        Plotting.create_axis!(fig_data, state)
        (fig_data, state, dataset)
    end

    function cleanup(dataset)
        GLMakie.closeall()
        close(dataset.ds)
    end

    # ============================================
    #  Plot Struct
    # ============================================

    @testset "Animated-axis label" begin
        @testset "Template compilation" begin
            dataset = make_temp_dataset()
            cfg = Plotting.AnimLabelConfig(
                Constants.NUMBER_FORMAT, Constants.DATETIME_FORMAT)
            compile(var, sel, pdim, animlabel = true) =
                Plotting.compile_animlabel(dataset, var, sel, pdim,
                                           animlabel, cfg)

            # the default template: one static piece, one value slot
            segs = compile("3d_float", ["lon", "lat"], "time")
            @test [seg.dynamic for seg in segs] == [false, true]
            @test segs[1].text == "time: "
            @test segs[2].template == "{value}"
            @test all(seg.width > 0 for seg in segs)

            # several dynamic placeholders each get their own slot
            segs = compile("3d_float", ["lon", "lat"], "time",
                           "t = {rawvalue} s (frame {index})")
            @test [seg.dynamic for seg in segs] ==
                [false, true, false, true, false]
            @test [seg.template for seg in segs if seg.dynamic] ==
                ["{rawvalue}", "{index}"]
            @test [seg.text for seg in segs if !seg.dynamic] ==
                ["t = ", " s (frame ", ")"]

            # frame-independent placeholders become static text
            segs = compile("5d_float", ["lon", "lat"], "only_unit",
                           "{name} [{unit}]: {rawvalue}")
            @test segs[1].text == "only_unit [n/a]: "
            @test segs[2].template == "{rawvalue}"

            # nothing to label -> no segments
            @test isempty(compile("3d_float", ["lon", "lat"],
                                  Constants.NOT_SELECTED_LABEL))
            @test isempty(compile("3d_float", ["lon", "time"], "time"))
            @test isempty(compile("2d_float", ["lon", "lat"], "time"))
            @test isempty(compile("3d_float", ["lon", "lat"], "time", false))
            @test isempty(compile("3d_float", ["lon", "lat"], "time", ""))
            close(dataset.ds)
        end

        @testset "Slot rendering and sizing" begin
            dataset = make_temp_dataset()
            cfg = Plotting.AnimLabelConfig(
                Constants.NUMBER_FORMAT, Constants.DATETIME_FORMAT)

            @test Plotting.render_slot(dataset, "float_dim", 4,
                "{rawvalue}", cfg) == "1.6"
            @test Plotting.render_slot(dataset, "float_dim", 4,
                "{index}", cfg) == "4"
            # a DateTime axis renders without a unit suffix
            @test Plotting.render_slot(dataset, "time", 2,
                "{value}", cfg) == "1951-01-03 00:00:00"

            # the slot is sized from the widest rendering over the axis
            widest = Plotting.widest_slot_text(dataset, "float_dim",
                "{rawvalue}", cfg)
            @test length(widest) == 3          # "1.2" beats "1"/"2"
            # an unknown dimension yields an empty (zero-width) slot
            @test Plotting.widest_slot_text(dataset, "nope",
                "{rawvalue}", cfg) == ""

            @test Plotting.measure_text("time: ") > 0
            @test Plotting.measure_text("") == 0.0
            # a larger fontsize widens the measured slot
            @test Plotting.measure_text("time: ", 40) >
                Plotting.measure_text("time: ", 20)
            close(dataset.ds)
        end

        @testset "Uniform number format" begin
            # equal digit counts across the axis, chosen from the step
            @test Plotting.uniform_numfmt([0.0, 0.5, 1.0, 1.5, 2.0]) == "%.1f"
            @test Plotting.uniform_numfmt([0.0, 0.25, 0.5]) == "%.2f"
            @test Plotting.uniform_numfmt([1.0, 2.0, 3.0]) == "%.0f"
            @test Plotting.uniform_numfmt([0.0]) == "%.0f"
            @test Plotting.uniform_numfmt(Float64[]) == Constants.NUMBER_FORMAT
            # tiny magnitudes switch to scientific, mantissa digits
            # derived from the step: 1.5e-5, 1.6e-5, ...
            @test Plotting.uniform_numfmt(collect(1.5e-5:1e-6:2.0e-5)) == "%.1e"
            # huge magnitudes as well
            @test Plotting.uniform_numfmt([1e7, 2e7, 3e7]) == "%.0e"
            # the derived spec really renders uniformly
            @test Plotting.Data.format_number(1.0, "%.1f") == "1.0"
            @test Plotting.Data.format_number(0.5, "%.1f") == "0.5"

            dataset = make_temp_dataset()
            # float_dim = 1.0:0.2:2.0 -> one decimal everywhere
            @test Plotting.resolve_numfmt(dataset, "float_dim", "auto") == "%.1f"
            # an explicit spec wins over the derivation
            @test Plotting.resolve_numfmt(dataset, "float_dim", "%.3f") == "%.3f"
            # an unknown dimension falls back to the plain default
            @test Plotting.resolve_numfmt(dataset, "nope", "auto") ==
                Constants.NUMBER_FORMAT
            close(dataset.ds)
        end

        @testset "Animation display units" begin
            # Arrange: a playback dimension in plain seconds (5 days span)
            function make_seconds_dataset()
                file = tempname() * ".nc"
                NCDataset(file, "c") do ds
                    defVar(ds, "t", collect(0.0:43200.0:432000.0), ("t",),
                        attrib = OrderedDict("units" => "s"))
                    defVar(ds, "x", collect(1.0:5.0), ("x",))
                    defVar(ds, "u", rand(5, 11), ("x", "t"))
                end
                Data.CDFDataset([file])
            end

            dataset = make_seconds_dataset()
            settings = Plotting.FigureSettings()

            # Act & Assert: native by default, duration shape always derived
            config = Plotting.resolve_anim_config(dataset, "t", settings)
            @test config.unit === nothing
            @test config.numfmt == "%.0f"
            @test config.durspec == Data.DurationSpec(:d, :h, 0)

            # Act & Assert: an explicit unit converts the derived numfmt too
            settings.animunit[] = "d"
            config = Plotting.resolve_anim_config(dataset, "t", settings)
            @test config.unit == "d"
            @test config.numfmt == "%.1f"      # 0.0, 0.5, ... 5.0 days

            # Act & Assert: "auto" picks the unit from the axis magnitude
            settings.animunit[] = "auto"
            config = Plotting.resolve_anim_config(dataset, "t", settings)
            @test config.unit == "d"

            # Act & Assert: a family mismatch keeps native rendering
            settings.animunit[] = "km"
            config = Plotting.resolve_anim_config(dataset, "t", settings)
            @test config.unit === nothing
            @test config.numfmt == "%.0f"

            # Act & Assert: converted slots render through the shared config
            settings.animunit[] = "h"
            config = Plotting.resolve_anim_config(dataset, "t", settings)
            @test Plotting.render_slot(dataset, "t", 2, "{value}", config) ==
                "12 h"
            @test Plotting.render_slot(dataset, "t", 4, "{duration}",
                                       config) == "1d 12h"

            # Act & Assert: the static {unit} placeholder converts as well
            segs = Plotting.compile_animlabel(dataset, "u", ["x"], "t",
                "{name} [{unit}]: {rawvalue}", config)
            @test segs[1].text == "t [h]: "

            # Act & Assert: on a non-time axis a duration slot degrades to
            # a value slot, so the template survives pdim switches
            config = Plotting.resolve_anim_config(dataset, "x", settings)
            @test config.durspec === nothing
            segs = Plotting.compile_animlabel(dataset, "u", ["t"], "x",
                "{duration}", config)
            @test [seg.template for seg in segs if seg.dynamic] == ["{value}"]
            segs = Plotting.compile_animlabel(dataset, "u", ["x"], "t",
                "{duration}", Plotting.resolve_anim_config(dataset, "t", settings))
            @test [seg.template for seg in segs if seg.dynamic] == ["{duration}"]

            close(dataset.ds)
        end

        @testset "Dimensionless playback dimension" begin
            # Arrange: a playback dimension carrying units = "1"
            dataset = make_dimensionless_temp_dataset()
            settings = Plotting.FigureSettings()

            # Act: nothing to convert into, so the label stays native
            config = Plotting.resolve_anim_config(dataset, "one", settings)

            # Assert: neither the value nor the {unit} slot shows a unit
            @test config.unit === nothing
            @test config.durspec === nothing
            @test Plotting.render_slot(dataset, "one", 2, "{value}", config) ==
                "2"
            segs = Plotting.compile_animlabel(dataset, "frac", ["milli"],
                "one", "{name} [{unit}]: {value}", config)
            @test segs[1].text == "Ratio []: "

            # Act & Assert: no display unit can apply to a dimensionless axis
            @test Plotting.resolve_animunit(dataset, "one", "km",
                                            [1.0, 2.0]) === nothing
            @test Plotting.resolve_animunit(dataset, "one", "auto",
                                            [1.0, 2.0]) === nothing

            # Act & Assert: a look-alike unit still prints
            config = Plotting.resolve_anim_config(dataset, "milli", settings)
            @test Plotting.render_slot(dataset, "milli", 2, "{value}",
                                       config) == "2 1e-3"

            close(dataset.ds)
        end

        @testset "animunit setting" begin
            # Arrange: a full figure over the seconds dataset
            file = tempname() * ".nc"
            NCDataset(file, "c") do ds
                defVar(ds, "t", collect(0.0:43200.0:432000.0), ("t",),
                    attrib = OrderedDict("units" => "s"))
                defVar(ds, "x", collect(1.0:5.0), ("x",))
                defVar(ds, "u", rand(5, 11), ("x", "t"))
            end
            dataset = Data.CDFDataset([file])
            ui = UI.UIElements(dataset)
            plot_data = Plotting.PlotData(ui.state, dataset)
            fd = Plotting.FigureData(plot_data, ui)
            state = ui.state
            state.variable[] = "u"
            state.x_name[] = "x"
            playback = ui.main_menu.playback_menu
            playback.var.selection[] = "t"

            # Assert: the readout starts native
            @test playback.label.text[] == "  → t: 0 s"

            # Act & Assert: unknown spellings error and change nothing
            res = @test_logs (:error,) match_mode = :any begin
                Plotting.set_animunit!(fd, "furlong")
            end
            @test res == false
            @test fd.settings.animunit[] === nothing

            # Act & Assert: a wrong-family unit warns but is stored (it
            # applies once a compatible playback dimension is selected)
            res = @test_logs (:warn,) match_mode = :any begin
                Plotting.set_animunit!(fd, "km")
            end
            @test res == false
            @test fd.settings.animunit[] == "km"
            @test fd.anim_config[].unit === nothing
            @test playback.label.text[] == "  → t: 0 s"

            # Act & Assert: a valid unit reaches the label and the readout
            Plotting.set_animunit!(fd, "h")
            @test fd.anim_config[].unit == "h"
            @test state.anim_unit[] == "h"
            @test playback.label.text[] == "  → t: 0 h"

            # Act & Assert: "auto" resolves against the axis magnitude
            Plotting.set_animunit!(fd, "auto")
            @test fd.anim_config[].unit == "d"
            @test playback.label.text[] == "  → t: 0 d"

            # Act & Assert: switching off restores native values
            Plotting.set_animunit!(fd, nothing)
            @test fd.anim_config[].unit === nothing
            @test playback.label.text[] == "  → t: 0 s"

            # Assert: the settings default is off
            @test Plotting.get_default_value(fd, fd.settings, :animunit) ===
                nothing

            GLMakie.closeall()
            close(dataset.ds)
        end

        @testset "Settings defaults" begin
            settings = Plotting.FigureSettings()
            @test settings.animlabel[] == true
            @test settings.animlabelpos[] === Constants.ANIMLABEL_POSITION
            @test Constants.ANIMLABEL_POSITION === :title
            @test settings.animlabelnumfmt[] == Constants.ANIMLABEL_NUMFMT
            @test settings.animlabeldateformat[] == Constants.DATETIME_FORMAT
            @test settings.animlabelcorner[] === Constants.ANIMLABEL_CORNER
            @test settings.animlabelbg[] === Constants.ANIMLABEL_BACKGROUND
            @test settings.title[] === nothing
            @test settings.titlesize[] == Float64(Constants.TITLESIZE)
            @test settings.animlabelsize[] == Float64(Constants.LABELSIZE)
            @test settings.cbarlabel[] === nothing
            @test settings.cbarlabelsize[] == Float64(Constants.LABELSIZE)
            @test settings.cbarlabelcolor[] === Constants.CBARLABEL_COLOR
            @test settings.cbarlabelfont[] == Constants.CBARLABEL_FONT
            @test settings.cbarlabelrotation[] === nothing
            @test settings.cbarlabelpadding[] ==
                Float64(Constants.CBARLABEL_PADDING)
        end

        @testset "Overlay geometry and background" begin
            # each corner insets the box from its own axes corner
            wp = (800, 600)
            inset = Float64(Constants.ANIMLABEL_PADDING)
            r = Plotting.animlabel_overlay_rect(wp, :lt, 100.0, 30.0)
            @test r.origin[1] == inset && r.origin[2] == 600 - inset - 30
            r = Plotting.animlabel_overlay_rect(wp, :rb, 100.0, 30.0)
            @test r.origin[1] == 800 - inset - 100 && r.origin[2] == inset
            @test Plotting.animlabel_overlay_rect(wp, :lt, 100.0, 30.0).widths ==
                Vec2f(100, 30)

            # the background box is transparent and unstroked when disabled
            @test Plotting.animlabel_background_color(false) == (:white, 0.0)
            @test Plotting.animlabel_background_stroke(false) == 0
            @test Plotting.animlabel_background_color(true) ==
                Constants.ANIMLABEL_BACKGROUND_COLOR
            @test Plotting.animlabel_background_stroke(true) == 1
            # an explicit colour overrides the translucent default
            @test Plotting.animlabel_background_color((:black, 0.4)) == (:black, 0.4)
        end

        @testset "Title gives way to the label" begin
            fit = Plotting.fit_title_size
            bold = Plotting.title_font()
            text = "Eastward wind / Northward wind [m s-1]"
            full = Plotting.measure_text(text, 24, bold)
            @test full > 0

            # room to spare: the configured size is kept untouched
            @test fit(full + 10, text, 24) == 24.0
            @test fit(full, text, 24) == 24.0

            # too tight: shrunk exactly enough to fit beside the label
            fitted = fit(0.8 * full, text, 24)
            @test fitted ≈ 0.8 * 24 rtol = 0.02
            @test Plotting.measure_text(text, fitted, bold) <= 0.8 * full + 1

            # ... but never past the floor, and never on nothing to draw
            @test fit(1.0, text, 24) == Constants.TITLESIZE_MIN
            @test fit(0.0, text, 24) == Constants.TITLESIZE_MIN
            @test fit(10.0, "", 24) == 24.0

            # the bold face the title is drawn in is wider than the
            # regular one, which is why it has to be measured separately
            @test full > Plotting.measure_text(text, 24)
        end

        @testset "Colorbar height matches the axis" begin
            (fig_data, state, dataset) = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "heatmap")
            # 2D: the colorbar is pinned to the axis' on-screen height,
            # so an aspect-letterboxed axis keeps the two flush
            @test fig_data.cbar[] isa Colorbar
            h = fig_data.cbar[].height[]
            @test h isa Makie.GridLayoutBase.Fixed
            @test h.x == fig_data.ax[].scene.viewport[].widths[2]
            cleanup(dataset)
        end

        @testset "Label row integration" begin
            (fig_data, state, dataset) = arrange_and_create_axis(
                "3d_float", ["lon", "lat"], "heatmap")
            # selecting a playback dimension draws title + two segments
            state.pdim[] = "time"
            @test length(fig_data.anim_header[]) == 3
            # a frame change updates only the slot text observable
            state.dim_obs[]["time"] = 2
            notify(state.dim_obs)
            @test fig_data.anim_slots[1][] == "1951-01-03 00:00:00"
            # deselecting leaves only the title
            state.pdim[] = Constants.NOT_SELECTED_LABEL
            @test length(fig_data.anim_header[]) == 1
            cleanup(dataset)
        end
    end

    @testset "Pinned color range" begin
        kwc(pairs...) = OrderedDict{Symbol, Any}(pairs...)
        wait_scan(fd) = let t = fd.layers[1].crange_scan.task
            t === nothing || wait(t)
        end
        # Makie stores the attribute as a Vec2f; compare in Float32
        crange(fd) = Tuple(Plotting.primary(fd).colorrange[])
        function init_anim_figure(plot_type::String, var::String = "3d_float")
            (fd, state, dataset) = arrange_and_create_axis(
                var, ["lon", "lat"], plot_type)
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            wait_scan(fd)
            (fd, state, dataset)
        end

        @testset "Cycle pin" begin
            (fd, state, dataset) = init_anim_figure("heatmap")
            vals = dataset.ds["3d_float"][:, :, :]
            expected = Float32.((minimum(vals), maximum(vals)))
            @test crange(fd) == expected

            # advancing the playback frame leaves the pin untouched
            fd.ui.main_menu.coord_sliders.sliders["time"].value[] = 2
            @test crange(fd) == expected
            cleanup(dataset)
        end

        @testset "Modes" begin
            (fd, state, dataset) = init_anim_figure("heatmap")
            vals = dataset.ds["3d_float"][:, :, :]
            expected = Float32.((minimum(vals), maximum(vals)))

            # "frame" restores Makie's per-frame autoscaling
            Plotting.update_kwargs!(fd, kwc(:colorrange => "frame"))
            @test Plotting.primary(fd).colorrange[] == Makie.automatic

            # deleting the keyword returns to the cycle pin (cached)
            Plotting.update_kwargs!(fd, kwc())
            @test crange(fd) == expected

            # a manual tuple always wins
            Plotting.update_kwargs!(fd, kwc(:colorrange => (0.2, 0.8)))
            @test crange(fd) == (0.2f0, 0.8f0)
            Plotting.update_kwargs!(fd, kwc())
            @test crange(fd) == expected

            # unknown mode strings are rejected and change nothing
            @test_logs (:error,) match_mode = :any begin
                Plotting.update_kwargs!(fd, kwc(:colorrange => "bogus"))
            end
            @test crange(fd) == expected
            cleanup(dataset)
        end

        @testset "Manual range vs. a scan in flight" begin
            # Arrange: the cycle scan is still running when the keywords
            # arrive. apply_kwargs! yields while it waits for its render
            # cycles, and the scan used to land inside that window and
            # overwrite the manual range -- silently, nothing errored.
            (fd, state, dataset) = arrange_and_create_axis(
                "3d_float", ["lon", "lat"], "heatmap")
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            # the wait (and with it the yield) only runs with a window
            fd.fig.scene.events.window_open[] = true

            # Act: the reported keyword set, applied without awaiting
            # the scan
            Plotting.update_kwargs!(fd, kwc(
                :animlabel => true, :animlabelnumfmt => "%.2f",
                :colormap => :viridis, :colorrange => (0.2, 0.8),
                :figsize => (900, 700), :titlesize => 30,
                :xlabelsize => 22, :ylabelsize => 22, :title => "Demo"))
            wait_scan(fd)

            # Assert: the manual range holds, and so does everything else
            @test crange(fd) == (0.2f0, 0.8f0)
            @test fd.settings.titlesize[] == 30.0
            @test fd.ax[].xlabelsize[] == 22.0
            @test fd.settings.title[] == "Demo"

            # Act & Assert: a pin that lands even later is reconciled
            # away the next time the range is updated
            Plotting.apply_colorrange_pin!(
                fd, Plotting.colorrange_key(fd, :cycle), (0.0, 1.0))
            Plotting.update_colorrange!(fd)
            @test crange(fd) == (0.2f0, 0.8f0)
            cleanup(dataset)
        end

        @testset "Cycle vs data" begin
            (fd, state, dataset) = init_anim_figure("heatmap", "4d_float")
            all_vals = dataset.ds["4d_float"][:, :, :, :]
            slab = all_vals[:, :, :, 1]     # float_dim fixed at index 1
            @test crange(fd) == Float32.((minimum(slab), maximum(slab)))

            Plotting.update_kwargs!(fd, kwc(:colorrange => "data"))
            wait_scan(fd)
            @test crange(fd) == Float32.((minimum(all_vals), maximum(all_vals)))
            cleanup(dataset)
        end

        @testset "Contour levels" begin
            (fd, state, dataset) = arrange_and_create_axis(
                "3d_float", ["lon", "lat"], "contourf")
            # render once BEFORE the pin: Makie's compute graph types the
            # levels edge from this first resolve, and the pin must
            # convert into it (regression: a Vector could not)
            Makie.colorbuffer(fd.fig)
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            wait_scan(fd)
            vals = dataset.ds["3d_float"][:, :, :]
            levels = Plotting.primary(fd).levels[]
            @test levels isa AbstractVector
            @test first(levels) == minimum(vals)
            @test last(levels) == maximum(vals)
            Makie.colorbuffer(fd.fig)   # the pinned levels must render

            # frame mode hands the plot its own Int levels back
            Plotting.update_kwargs!(fd, kwc(:colorrange => "frame"))
            @test Plotting.primary(fd).levels[] isa Int
            Makie.colorbuffer(fd.fig)   # and that must render as well
            cleanup(dataset)
        end

        @testset "No playback dimension" begin
            (fd, state, dataset) = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "heatmap")
            @test fd.layers[1].crange_scan.applied_key === nothing
            @test Plotting.primary(fd).colorrange[] == Makie.automatic
            cleanup(dataset)
        end

        @testset "Camera rotation" begin
            kwr(pairs...) = OrderedDict{Symbol, Any}(pairs...)

            # Arrange: a surface plot lives on an Axis3
            (fd, state, dataset) = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "surface")
            @test fd.ax[] isa Axis3

            # Act & Assert: horizontal rotation advances the azimuth
            Plotting.update_kwargs!(fd, kwr(:rotate => 90))
            azimuth = fd.ax[].azimuth[]
            Plotting.rotate_camera!(fd, 0.1)
            @test fd.ax[].azimuth[] ≈ azimuth + deg2rad(9)

            # Act & Assert: a lag spike is clamped, not a camera jolt
            azimuth = fd.ax[].azimuth[]
            Plotting.rotate_camera!(fd, 5.0)
            @test fd.ax[].azimuth[] ≈ azimuth + deg2rad(9)

            # Act & Assert: vertical rotation bounces at the default
            # upper limit (elevation 80°)
            Plotting.update_kwargs!(fd, kwr(:rotate => 0, :rotatev => 90))
            fd.ax[].elevation[] = deg2rad(79)
            @test fd.camera_vdir[] == 1.0
            Plotting.rotate_camera!(fd, 0.1)   # would overshoot: clamps
            @test fd.ax[].elevation[] ≈ deg2rad(80)
            @test fd.camera_vdir[] == -1.0
            Plotting.rotate_camera!(fd, 0.1)   # now heading down
            @test fd.ax[].elevation[] < deg2rad(80)

            # Act & Assert: custom vertical limits bound the bounce
            Plotting.update_kwargs!(fd, kwr(:rotatev => 90,
                                            :rotatevlim => (10, 30)))
            fd.ax[].elevation[] = deg2rad(29)
            fd.camera_vdir[] = 1.0
            Plotting.rotate_camera!(fd, 0.1)
            @test fd.ax[].elevation[] ≈ deg2rad(30)
            @test fd.camera_vdir[] == -1.0

            # Act & Assert: outside the limits (a dragged camera) the
            # view travels back smoothly instead of snapping
            fd.ax[].elevation[] = deg2rad(-20)
            Plotting.rotate_camera!(fd, 0.1)
            @test fd.ax[].elevation[] ≈ deg2rad(-11)

            # Act & Assert: an azimuth sector turns the orbit into a sweep
            Plotting.update_kwargs!(fd, kwr(:rotate => 90,
                                            :rotatelim => (-45, 45)))
            fd.ax[].azimuth[] = deg2rad(44)
            fd.camera_hdir[] = 1.0
            Plotting.rotate_camera!(fd, 0.1)
            @test fd.ax[].azimuth[] ≈ deg2rad(45)
            @test fd.camera_hdir[] == -1.0

            # Act & Assert: a negative speed seeds the direction
            Plotting.update_kwargs!(fd, kwr(:rotatev => -90))
            @test fd.camera_vdir[] == -1.0

            # Act & Assert: unusable limits are rejected
            @test_logs (:error,) match_mode = :any begin
                Plotting.set_rotatevlim!(fd, (50, 10))
            end
            @test fd.settings.rotatevlim[] == (0.0, 80.0)

            # Act & Assert: deleting the keywords stops the motion
            Plotting.update_kwargs!(fd, kwr())
            azimuth, elevation = fd.ax[].azimuth[], fd.ax[].elevation[]
            Plotting.rotate_camera!(fd, 0.1)
            @test fd.ax[].azimuth[] == azimuth
            @test fd.ax[].elevation[] == elevation
            cleanup(dataset)

            # Arrange & Assert: a 2D axis stores the setting but stays put
            (fd, state, dataset) = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "heatmap")
            Plotting.update_kwargs!(fd, kwr(:rotate => 10))
            @test fd.settings.rotate[] == 10.0
            Plotting.rotate_camera!(fd, 0.1)   # no Axis3: nothing happens
            cleanup(dataset)
        end

        @testset "Size gate" begin
            old = Plotting.DataLimits.AUTO_SCAN_ELEMENTS[]
            Plotting.DataLimits.AUTO_SCAN_ELEMENTS[] = 10
            try
                (fd, state, dataset) = arrange_and_create_axis(
                    "3d_float", ["lon", "lat"], "heatmap")
                # over the gate: no scan, per-frame scaling, one hint
                @test_logs (:info,) match_mode = :any begin
                    fd.ui.main_menu.playback_menu.var.selection[] = "time"
                end
                @test fd.layers[1].crange_scan.applied_key === nothing
                @test Plotting.primary(fd).colorrange[] == Makie.automatic

                # an explicit request bypasses the gate
                Plotting.update_kwargs!(fd, kwc(:colorrange => "cycle"))
                wait_scan(fd)
                vals = dataset.ds["3d_float"][:, :, :]
                expected = Float32.((minimum(vals), maximum(vals)))
                @test crange(fd) == expected

                # once cached, even the gated default keeps the pin
                Plotting.update_kwargs!(fd, kwc())
                @test crange(fd) == expected
                cleanup(dataset)
            finally
                Plotting.DataLimits.AUTO_SCAN_ELEMENTS[] = old
            end
        end
    end

    @testset "Axis display units" begin

        # Arrange - helpers: a dataset with x/y coordinates in meters
        function make_meter_dataset()
            file = tempname() * ".nc"
            NCDataset(file, "c") do ds
                defVar(ds, "x", collect(range(0.0, 2.0e6, 41)), ("x",),
                    attrib = OrderedDict("units" => "m"))
                defVar(ds, "y", collect(range(0.0, 1.0e6, 21)), ("y",),
                    attrib = OrderedDict("units" => "m"))
                defVar(ds, "eta", rand(41, 21), ("x", "y"),
                    attrib = OrderedDict(
                        "units" => "cm", "long_name" => "Surface elevation"))
            end
            Data.CDFDataset([file])
        end

        function init_meter_figure(plot_type::String)
            dataset = make_meter_dataset()
            ui = UI.UIElements(dataset)
            plot_data = Plotting.PlotData(ui.state, dataset)
            fd = Plotting.FigureData(plot_data, ui)
            state = ui.state
            state.variable[] = "eta"
            state.x_name[] = "x"
            state.y_name[] = "y"
            state.plot_type_name[] = plot_type
            Plotting.create_axis!(fd, state)
            (fd, state, dataset)
        end

        kw(pairs...) = OrderedDict{Symbol, Any}(pairs...)

        @testset "UnitTicks placement and labels" begin
            # Act: meters rendered as km over 0..2000 km
            vals, labels = Makie.get_ticks(
                Plotting.UnitTicks(1e-3), identity, Makie.automatic, 0.0, 2.0e6)

            # Assert: ticks sit on round display values, mapped back to native
            @test vals == [0.0, 5.0e5, 1.0e6, 1.5e6, 2.0e6]
            @test labels == ["0", "500", "1000", "1500", "2000"]

            # Act: a non-power-of-ten factor (seconds rendered as minutes)
            vals, labels = Makie.get_ticks(
                Plotting.UnitTicks(1 / 60), identity, Makie.automatic,
                0.0, 7200.0)

            # Assert: placement happens in display space, so minutes are round
            @test labels == ["0", "20", "40", "60", "80", "100", "120"]
            @test vals ≈ 60.0 .* [0.0, 20.0, 40.0, 60.0, 80.0, 100.0, 120.0]

            # Act & Assert: a user formatter keeps native values
            fmt = vs -> [string(round(Int, v)) for v in vs]
            _, labels = Makie.get_ticks(
                Plotting.UnitTicks(1e-3), identity, fmt, 0.0, 2.0e6)
            @test labels == ["0", "500000", "1000000", "1500000", "2000000"]
        end

        @testset "Unit settings on the axis" begin
            # Arrange
            (fd, state, dataset) = init_meter_figure("heatmap")
            @test fd.ax[].xticks[] == Makie.automatic
            @test fd.plot_data.labels.xlabel[] == "x [m]"

            # Act: enable km on both axes through the kwargs path
            Plotting.update_kwargs!(fd, kw(:xunit => "km", :yunit => "km"))

            # Assert: unit ticks and converted label brackets
            @test fd.settings.xunit[] == "km"
            @test fd.ax[].xticks[] == Plotting.UnitTicks(1e-3)
            @test fd.ax[].yticks[] == Plotting.UnitTicks(1e-3)
            @test fd.plot_data.labels.xlabel[] == "x [km]"
            @test fd.ax[].xlabel[] == "x [km]"

            # Act: removing the kwargs restores native rendering
            Plotting.update_kwargs!(fd, kw())

            # Assert
            @test fd.settings.xunit[] === nothing
            @test fd.ax[].xticks[] == Makie.automatic
            @test fd.plot_data.labels.xlabel[] == "x [m]"

            # Assert: the settings default is off
            @test Plotting.get_default_value(fd, fd.settings, :xunit) === nothing

            cleanup(dataset)
        end

        @testset "Rejected units" begin
            # Arrange
            (fd, state, dataset) = init_meter_figure("heatmap")

            # Act & Assert: unknown spellings error and change nothing
            res = @test_logs (:error,) match_mode = :any begin
                Plotting.set_xunit!(fd, "furlong")
            end
            @test res == false
            @test fd.settings.xunit[] === nothing

            # Act & Assert: a known unit of the wrong family warns
            res = @test_logs (:warn,) match_mode = :any begin
                Plotting.set_xunit!(fd, "bar")
            end
            @test res == true
            Plotting.set_xunit!(fd, nothing)

            # Act & Assert: through the kwargs path the warning reverts it
            @suppress Plotting.update_kwargs!(fd, kw(:xunit => "furlong"))
            @test fd.settings.xunit[] === nothing
            @test fd.ax[].xticks[] == Makie.automatic

            cleanup(dataset)
        end

        @testset "Variable axes stay native" begin
            # Arrange: a 1D line plot shows the variable on the y axis
            (fd, state, dataset) = init_meter_figure("line")

            # Act
            Plotting.update_kwargs!(fd, kw(:xunit => "km", :yunit => "km"))

            # Assert: the coordinate axis converts, the variable axis does not
            @test fd.ax[].xticks[] == Plotting.UnitTicks(1e-3)
            @test fd.ax[].yticks[] == Makie.automatic
            cleanup(dataset)

            # Arrange: a surface plot shows the variable on the z axis
            (fd, state, dataset) = init_meter_figure("surface")

            # Act (zunit would warn here: no z coordinate is selected)
            Plotting.update_kwargs!(fd, kw(:xunit => "km"))

            # Assert
            @test fd.ax[] isa Axis3
            @test fd.ax[].xticks[] == Plotting.UnitTicks(1e-3)
            @test !(fd.ax[].zticks[] isa Plotting.UnitTicks)
            cleanup(dataset)
        end

        @testset "User tick overrides win" begin
            # Arrange
            (fd, state, dataset) = init_meter_figure("heatmap")

            # Act: an explicit xticks kwarg beats the unit ticks
            Plotting.update_kwargs!(fd, kw(:xunit => "km",
                                           :xticks => [0.0, 1.0e6, 2.0e6]))

            # Assert
            @test fd.ax[].xticks[] == [0.0, 1.0e6, 2.0e6]

            # Act: deleting the override restores the unit ticks
            Plotting.update_kwargs!(fd, kw(:xunit => "km"))

            # Assert
            @test fd.ax[].xticks[] == Plotting.UnitTicks(1e-3)
            cleanup(dataset)
        end
    end

    @testset "Plot Struct" begin

        @testset "Number of Plot Options" begin
            number_of_plots = length(keys(Plotting.PLOT_TYPES))
            @test length(Plotting.get_plot_options(3)) == number_of_plots
            @test length(Plotting.get_plot_options(2)) < number_of_plots
            @test length(Plotting.get_plot_options(1)) < length(Plotting.get_plot_options(2))
        end

        @testset "Plot Struct Fields" begin
            for (name, plot) in Plotting.PLOT_TYPES
                @test plot isa Plotting.Plot
                @test plot.type == name
                @test plot.ndims in (0, 1, 2, 3)
                @test plot.func isa Function
                @test plot.make_axis isa Function
            end
        end

        @testset "Plot Options Functions" begin
            @test "volume" ∈ Plotting.get_plot_options(4)
            @test "volume" ∈ Plotting.get_plot_options(3)
            @test "heatmap" ∈ Plotting.get_plot_options(2)
            @test "volume" ∉ Plotting.get_plot_options(2)
            @test "line" ∈ Plotting.get_plot_options(1)
            @test "heatmap" ∉ Plotting.get_plot_options(1)
            @test Constants.NOT_SELECTED_LABEL ∈ Plotting.get_plot_options(0)
        end

        @testset "Fallback Plot Function" begin
            @test Plotting.get_fallback_plot(4) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(3) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_fallback_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_fallback_plot(0) == Constants.NOT_SELECTED_LABEL
        end

        @testset "Dimension Plot Function" begin
            @test Plotting.get_dimension_plot(4) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(3) == Constants.PLOT_DEFAULT_3D
            @test Plotting.get_dimension_plot(2) == Constants.PLOT_DEFAULT_2D
            @test Plotting.get_dimension_plot(1) == Constants.PLOT_DEFAULT_1D
            @test Plotting.get_dimension_plot(0) == Constants.NOT_SELECTED_LABEL
        end

        @testset "Plot Functions" begin
            # Arrange - helper functions
            function create_dummy_data(number_of_dims)
                x = collect(1:5)
                y = number_of_dims >= 2 ? collect(1:6) : nothing
                z = number_of_dims == 3 ? collect(1:7) : nothing
                d = number_of_dims == 1 ? rand(length(x)) :
                    number_of_dims == 2 ? rand(length(x), length(y)) :
                    number_of_dims == 3 ? rand(length(x), length(y), length(z)) :
                    nothing
                (Observable(x), Observable(y), Observable(z), Observable(d))
            end

            # Arrange - create a temporary figure and dataset
            dataset = make_temp_dataset()
            ui = UI.UIElements(dataset)
            plot_data = Plotting.PlotData(ui.state, dataset)
            fd = Plotting.FigureData(plot_data, ui)
            fig = fd.fig

            for (name, plot) in Plotting.PLOT_TYPES
                # Act
                empty!(fig)
                (x, y, z, d) = create_dummy_data(plot.ndims)
                ax = plot.make_axis(fd)
                # a vector type draws two components, so it gets two
                components = Tuple(d for _ in 1:plot.nfields)
                plotobj = plot.func(fd, ax, 1, x, y, z, components...)

                # Assert
                plot.type === Constants.NOT_SELECTED_LABEL && continue  # Skip the Info plot as it does nothing
                @test !isempty(fig.content)  # Ensure something was plotted
                @test plotobj isa Makie.AbstractPlot
            end

            # Cleanup
            GLMakie.closeall()
        end

        @testset "Compute Aspect Ratio" begin
            @testset "2D Aspect Ratio" begin
                # Arrange - helper function
                function assert_aspect_2d(x, y, expected;
                    atol = 0.01, kwargs = OrderedDict{Symbol, Any}(), fig_widths = Vec{2, Int}(800, 600))
                    aspect = Plotting.compute_aspect(kwargs, x, y, fig_widths)
                    @test aspect ≈ expected atol=atol
                end

                # Act & Assert: Reasonable aspect ratios
                assert_aspect_2d(collect(1:5), collect(1:5), 1.0)
                assert_aspect_2d(collect(1:5), collect(1:0.2:3.2), 4/2.2)
                assert_aspect_2d(rand(1000), rand(1000), 1.0, atol=0.1)  # should fail 1 in ~10^500 times
                assert_aspect_2d([0.2, -0.4, 0.4], [3.1, 0.1, 0.7], 0.8/3.0)

                # Act & Assert: Extreme aspect ratios should fall back to figure aspect
                assert_aspect_2d([0.1, 100.0, 32], [0.2, 0.3, 0.4], 800/600)
                assert_aspect_2d([0.1, 0.2, 0.3], [0.1, 100.0, 32], 800/600)

                # Act & Assert: User-defined aspect ratio should override everything
                assert_aspect_2d(collect(1:5), collect(1:5), 2.0,
                    kwargs=OrderedDict{Symbol, Any}(:aspect => 2.0))
            end

            @testset "3D Aspect Ratio" begin
                # Arrange - helper function
                function assert_aspect_3d(x, y, z, expected;
                    atol = 0.01, kwargs = OrderedDict{Symbol, Any}(), ndims = 3)
                    aspect = Plotting.compute_aspect(kwargs, ndims, x, y, z)
                    for (a, b) in zip(aspect, expected)
                        @test a ≈ b atol=atol
                    end
                end

                # Act & Assert: Reasonable aspect ratios
                assert_aspect_3d(collect(1:5), collect(1:5), collect(1:5), (1.0, 1.0, 1.0))
                assert_aspect_3d(collect(1:4), collect(1:5), collect(1:6), (3/4, 1.0, 5/4))
                assert_aspect_3d(collect(1:5), collect(1:0.2:3.2), collect(1:0.1:4.1), (4/2.2, 2.2/2.2, 3.1/2.2))
                assert_aspect_3d(rand(1000), rand(1000), rand(1000), (1.0, 1.0, 1.0), atol=0.1)
                assert_aspect_3d([0.2, -0.4, 0.4], [3.1, 0.1, 0.7], [0.5, 0.6, -0.2], (0.8/3.0, 3.0/3.0, 0.8/3.0))

                # Act & Assert: Extreme aspect ratios should fall back to default
                assert_aspect_3d([0.1, 100.0, 32], [0.2, 0.3, 0.4], [0.5, 0.6, -0.2], (1.0, 1.0, 0.8/0.2))
                assert_aspect_3d([0.1, 0.2, 0.3], [0.1, 100.0, 32], [0.5, 0.6, -0.2], (1.0, 1.0, 1.0))
                assert_aspect_3d([0.1, 0.2, 0.3], [0.1, 0.2, 0.3], [0.5, 100.0, -0.2], (1.0, 1.0, 1.0))

                # Act & Assert: For 2D data, z aspect should be fixed to 0.4
                assert_aspect_3d(collect(1:5), collect(1:5), collect(1:5), (1.0, 1.0, 0.4), ndims=2)
                assert_aspect_3d(collect(1:4), collect(1:5), collect(1:6), (3/4, 1.0, 0.4), ndims=2)

                # Act & Assert: User-defined aspect ratio should override everything
                assert_aspect_3d(collect(1:5), collect(1:5), collect(1:5), (2.0, 1.0, 0.5),
                    kwargs=OrderedDict{Symbol, Any}(:aspect => (2.0, 1.0, 0.5)))
                assert_aspect_3d(collect(1:5), collect(1:5), collect(1:5), (1.0, 1.0, 0.2),
                    kwargs=OrderedDict{Symbol, Any}(:aspect => (0.2)), ndims=2)
            end

            @testset "Aspect Ratio in Axis Creation" begin
                @testset "2D axis with 2D data" begin
                    # Arrange
                    (fig_data, state, dataset) = arrange_and_create_axis("5d_float", ["lon"], "line")

                    # Assert
                    @test fig_data.ax[] isa Axis
                    @test isnothing(fig_data.ax[].aspect[])  # should be nothing for 1D plots

                    # Cleanup
                    cleanup(dataset)
                end

                @testset "2D axis with 2D data" begin
                    # Arrange
                    (fig_data, state, dataset) = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")

                    # Assert
                    @test fig_data.ax[] isa Axis
                    @test fig_data.ax[].aspect[] ≈ 4 / 6

                    # Cleanup
                    cleanup(dataset)
                end

                @testset "3D axis with 2D data" begin
                    # Arrange
                    (fig_data, state, dataset) = arrange_and_create_axis("5d_float", ["lon", "lat"], "surface")

                    # Assert
                    @test fig_data.ax[] isa Axis3
                    for (a, b) in zip(fig_data.ax[].aspect[], (4 / 6, 1.0, 0.4))
                        @test a ≈ b atol=0.1  # should be close to default 3D aspect ratio
                    end

                    # Cleanup
                    cleanup(dataset)
                end

                @testset "3D axis with 3D data" begin
                    # Arrange
                    (fig_data, state, dataset) = arrange_and_create_axis("5d_float", ["lon", "lat", "only_long"], "volume")

                    # Assert
                    @test fig_data.ax[] isa Axis3
                    for (a, b) in zip(fig_data.ax[].aspect[], (4 / 6, 1.0, 3 / 6))
                        @test a ≈ b atol=0.1  # should be close to default 3D aspect ratio
                    end

                    # Cleanup
                    cleanup(dataset)
                end

            end
        end
    end

    # ============================================
    #  Figure Labels
    # ============================================

    @testset "Figure Labels" begin

        # Arrange - helper function
        function init_figure_labels()
            dataset = make_temp_dataset()
            ui = UI.UIElements(dataset)
            # built through PlotData so the labels share its settings object
            labels = Plotting.PlotData(ui.state, dataset).labels
            (labels, ui.state, dataset)
        end

        @testset "Default Labels" begin
            # Arrange
            (labels, state, dataset) = init_figure_labels()

            # Assert
            @test labels.title[] == "1d_float"
            @test labels.xlabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.ylabel[] == Constants.NOT_SELECTED_LABEL
            @test labels.zlabel[] == Constants.NOT_SELECTED_LABEL

            # Cleanup
            cleanup(dataset)
        end

        @testset "Updated Labels" begin
            # Arrange
            (labels, state, dataset) = init_figure_labels()

            # Act: change variable to something with long_name and units
            state.variable[] = "both_atts_var"
            # Assert
            @test labels.title[] == "Both [m/s]"

            # Act: change x to something with only units
            state.x_name[] = "only_unit"
            # Assert
            @test labels.xlabel[] == "only_unit [n/a]"

            # Act: change y to something with only long_name            
            state.y_name[] = "untaken"
            # Assert
            @test labels.ylabel[] == "untaken"

            # Cleanup
            cleanup(dataset)
        end
    end

    # ============================================
    #  Plot Data
    # ============================================

    @testset "Plot Data" begin
        # Arrange - helper function
        function init_plot_data()
            dataset = make_temp_dataset()
            ui = UI.UIElements(dataset)

            plot_data = Plotting.PlotData(ui.state, dataset)
            (plot_data, ui.state, dataset)
        end

        @testset "Types" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()

            # Assert
            @test plot_data isa Plotting.PlotData
            @test plot_data.plot_type isa Observable{Plotting.Plot}
            @test plot_data.sel_dims isa Observable{Vector{String}}
            @test plot_data.x isa Observable
            @test plot_data.y isa Observable
            @test plot_data.z isa Observable
            @test plot_data.d isa Vector
            @test plot_data.labels isa Plotting.FigureLabels

            # Cleanup
            cleanup(dataset)
        end

        @testset "Initial Values" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES[Constants.NOT_SELECTED_LABEL]
            @test plot_data.sel_dims[] == String[]
            @test plot_data.x[] == collect(Float64, 1:1)
            @test plot_data.y[] == collect(Float64, 1:1)
            @test plot_data.z[] == collect(Float64, 1:1)
            for i in 1:3
                @test plot_data.d[1][1][i] isa Observable
                @test plot_data.d[1][1][i][] === nothing
            end

            # cleanup
            cleanup(dataset)
        end

        @testset "Selected Dimensions" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"

            # Act: select x and y dimensions
            state.x_name[] = "lon"
            state.y_name[] = "lat"

            # Assert
            @test length(plot_data.x[]) == 5
            @test length(plot_data.y[]) == 7
            @test length(plot_data.z[]) == 1

            # Act: deselect y dimension
            state.y_name[] = Constants.NOT_SELECTED_LABEL

            # Assert
            @test length(plot_data.x[]) == 5
            @test length(plot_data.y[]) == 1
            @test length(plot_data.z[]) == 1

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Arrays 1D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.plot_type_name[] = "line"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["line"]
            @test plot_data.sel_dims[] == ["lon"]
            @test plot_data.d[1][1][1][].size == (5,)
            @test plot_data.d[1][1][2][] === nothing
            @test plot_data.d[1][1][3][] === nothing

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Arrays 2D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["heatmap"]
            @test plot_data.sel_dims[] == ["lon", "lat"]
            @test plot_data.d[1][1][1][] === nothing
            @test plot_data.d[1][1][2][].size == (5, 7)
            @test plot_data.d[1][1][3][] === nothing

            # cleanup
            cleanup(dataset)
        end
            
        @testset "Data Arrays 3D" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"

            # Assert
            @test plot_data.plot_type[] == Plotting.PLOT_TYPES["volume"]
            @test plot_data.sel_dims[] == ["lon", "lat", "only_long"]
            @test plot_data.d[1][1][1][] === nothing
            @test plot_data.d[1][1][2][] === nothing
            @test plot_data.d[1][1][3][].size == (5, 7, 4)

            # cleanup
            cleanup(dataset)
        end

        @testset "Data at Dimension Change" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act
            state.x_name[] = "only_unit"

            # Assert
            @test plot_data.sel_dims[] == ["only_unit", "lat"]
            @test plot_data.d[1][1][2][].size == (3, 7)

            # cleanup
            cleanup(dataset)
        end

        @testset "Data Update Switch" begin
            # Arrange
            (plot_data, state, dataset) = init_plot_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act: disable updates
            plot_data.update_data_switch[] = false
            x_ori = plot_data.x[]
            d_ori = plot_data.d[1][1][1][]
            state.x_name[] = "lat"  # change x dimension
            state.variable[] = "2d_float"  # change variable
            state.plot_type_name[] = "line"  # change plot type

            # Assert: data should not have changed
            @test plot_data.x[] == x_ori
            @test plot_data.d[1][1][1][] == d_ori

            # Act: enable updates
            plot_data.update_data_switch[] = true

            # Assert: data should now reflect the changes
            @test length(plot_data.x[]) == 7
            @test plot_data.d[1][1][1][].size == (7,)

            # cleanup
            cleanup(dataset)
        end

    end

    # ============================================
    #  Figure Data
    # ============================================

    @testset "Figure Data" begin
            

        @testset "Types" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()

            # Assert
            @test fig_data isa Plotting.FigureData
            @test fig_data.fig isa Figure
            @test fig_data.plot_data isa Plotting.PlotData
            @test fig_data.ax isa Observable{Union{Makie.AbstractAxis, Nothing}}
            @test fig_data.layers[1].plot_obj isa Observable{Union{Makie.AbstractPlot, Nothing}}
            @test fig_data.cbar isa Observable{Union{Colorbar, Nothing}}
            @test fig_data.settings isa Plotting.FigureSettings

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 1D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lat"
            state.plot_type_name[] = "line"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test fig_data.ax[].xlabel[] == "lat"
            @test fig_data.ax[].ylabel[] == ""
            # the title lives in the layout Label, not on the axis
            @test fig_data.title_text[] == "5d_float"
            @test Plotting.primary(fig_data) isa Lines
            @test fig_data.cbar[] === nothing

            # Act - change observables
            state.x_name[] = "lon"
            state.variable[] = "both_atts_var"

            # Assert
            @test fig_data.title_text[] == "Both [m/s]"
            @test fig_data.ax[].xlabel[] == "lon"

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 2D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "lat"
            # the title lives in the layout Label, not on the axis
            @test fig_data.title_text[] == "5d_float"
            @test Plotting.primary(fig_data) isa Heatmap
            @test fig_data.cbar[] isa Colorbar

            # Act - change observables
            state.x_name[] = "lon"
            state.y_name[] = "float_dim"
            state.variable[] = "2d_gap"

            # Assert
            @test fig_data.title_text[] == "2d_gap"
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "float_dim"

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 2D with 3D Axis" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "2d_gap"
            state.x_name[] = "lon"
            state.y_name[] = "float_dim"
            state.plot_type_name[] = "surface"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "float_dim"
            @test fig_data.ax[].zlabel[] == ""
            @test fig_data.title_text[] == "2d_gap"
            @test Plotting.primary(fig_data) isa Surface
            @test fig_data.cbar[] isa Colorbar

            # Cleanup
            cleanup(dataset)
        end

        @testset "Plot 3D" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"

            # Act
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test fig_data.ax[].xlabel[] == "lon"
            @test fig_data.ax[].ylabel[] == "lat"
            @test fig_data.ax[].zlabel[] == "Long"
            # the title lives in the layout Label, not on the axis
            @test fig_data.title_text[] == "5d_float"
            @test Plotting.primary(fig_data) isa Volume
            @test fig_data.cbar[] isa Colorbar

            # Act - change observables
            state.x_name[] = "float_dim"

            # Assert
            @test fig_data.ax[].xlabel[] == "float_dim"

            # Cleanup
            cleanup(dataset)
        end

        @testset "Change Plot Type" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)

            # Act - change to a 3D plot type
            state.plot_type_name[] = "surface"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test Plotting.primary(fig_data) isa Surface
            @test fig_data.cbar[] isa Colorbar

            # Cleanup
            cleanup(dataset)
        end

        @testset "Change Plot Dimension" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)

            # Act - change to a 3D plot type
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis3
            @test Plotting.primary(fig_data) isa Volume
            @test fig_data.cbar[] isa Colorbar

            # Act - change to a 1D plot type
            state.plot_type_name[] = "line"
            Plotting.create_axis!(fig_data, state)

            # Assert
            @test fig_data.ax[] isa Axis
            @test Plotting.primary(fig_data) isa Lines
            @test fig_data.cbar[] === nothing

            # Cleanup
            cleanup(dataset)
        end

        @testset "Apply Kwargs" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fig_data, state)
            kwarg_text = fig_data.ui.main_menu.plot_menu.plot_kw.stored_string

            # Act - set some kwargs
            kwarg_text[] = "colorrange = (0.2, 0.8), colormap=:ice, titlevisible = false, label=\"My Label\"";

            # wait until all tasks are finished
            [wait(t) for t in fig_data.tasks[]]

            # Assert
            @test Plotting.primary(fig_data).colorrange.parent.value == (0.2, 0.8)
            @test Plotting.primary(fig_data).colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false
            @test fig_data.cbar[].label[] == "My Label"

            # Act - change to a 3D plot type
            state.z_name[] = "only_long"
            state.plot_type_name[] = "volume"
            Plotting.create_axis!(fig_data, state)

            # wait until all tasks are finished
            [wait(t) for t in fig_data.tasks[]]

            # Assert - the kwargs should still apply
            @test Plotting.primary(fig_data).colorrange.parent.value == (0.2, 0.8)
            @test Plotting.primary(fig_data).colormap.parent.value == :ice
            @test fig_data.ax[].titlevisible[] == false
            @test fig_data.cbar[].label[] == "My Label"

            # Cleanup
            cleanup(dataset)
        end
        @testset "Apply Bad Kwargs" begin
            # Arrange
            (fig_data, state, dataset) = init_figure_data()
            state.variable[] = "5d_float"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.plot_type_name[] = "contour"
            kwarg_text = fig_data.ui.main_menu.plot_menu.plot_kw.stored_string
            Plotting.create_axis!(fig_data, state)

            # Act & Assert - set nonexistent kwarg
            @test_logs (:warn, r"Property nonexistent not found in any plot object") begin
                kwarg_text[] = "nonexistent = 123, colormap = :ice"
                [wait(t) for t in fig_data.tasks[]]
            end

            # Cleanup
            cleanup(dataset)
        end


    end

    # ============================================
    #  Figure Settings
    # ============================================

    @testset "FiguresSettings" begin

        @testset "Resize Figure" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "contour")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
            settings = fd.settings

            # Assert default size
            @test settings.figsize[] == Constants.FIGSIZE

            # Act - resize figure via method
            new_size = (100, 100)
            Plotting.resize_figure!(fd, new_size)
            
            # Assert
            function assert_fig_size(fig, expected_size)
                actual_size = fig.scene.viewport[].widths
                @test actual_size == [expected_size[1], expected_size[2]]
                @test settings.figsize[] == expected_size
            end
            assert_fig_size(fd.fig, new_size)

            # resize figure via apply_figure_settings!
            new_size2 = (300, 150)
            Plotting.apply_figure_settings!(fd, :figsize, new_size2)
            assert_fig_size(fd.fig, new_size2)

            # resize figure via kwarg
            kwarg_text[] = "figsize = $(new_size)"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished
            assert_fig_size(fd.fig, new_size)

            # resize figure with bad value
            @test_warn "Value for figsize must be of type" begin
                Plotting.apply_figure_settings!(fd, :figsize, (100.0, 200.0)) # wrong type
                assert_fig_size(fd.fig, new_size)  # figsize should not have changed
            end

            @test_warn "Value for figsize must be of type" begin
                Plotting.apply_figure_settings!(fd, :figsize, (100, 200, 300))  # wrong length
                assert_fig_size(fd.fig, new_size)  # figsize should not have changed
            end

            # Cleanup
            cleanup(dataset)
        end

        @testset "cbar kwarg" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Assert Check that a colorbar is present
            @test fd.cbar[] isa Colorbar

            # Act - remove colorbar via kwarg
            kwarg_text[] = "cbar = false"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.cbar[] === nothing

            # Act - add colorbar via kwarg
            kwarg_text[] = "cbar = true"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.cbar[] isa Colorbar

            # Act - set to non-Bool value
            @test_warn "Value for cbar must be of type" begin
                kwarg_text[] = "cbar = 123"
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            end
            @test fd.cbar[] isa Colorbar  # should not have changed

            # Act - change to a plot type that does not support colorbar
            kwarg_text[] = ""
            state.plot_type_name[] = "line"
            Plotting.create_axis!(fd, state)

            # Assert Check that no colorbar is present
            @test fd.cbar[] === nothing

            # Cleanup
            cleanup(dataset)
        end

        @testset "cbarlabel" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "heatmap")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
            settings = fd.settings
            fonts = Makie.theme(fd.fig.scene).fonts

            # Assert: no label by default, and every styling attribute
            # sits on the value Makie itself would have used
            @test settings.cbarlabel[] === nothing
            @test fd.cbar[].label[] == ""
            @test fd.cbar[].labelsize[] == Float64(Constants.LABELSIZE)
            @test fd.cbar[].labelcolor[] == Constants.CBARLABEL_COLOR
            @test fd.cbar[].labelfont[] == to_font(fonts, :regular)
            @test fd.cbar[].labelrotation[] === Makie.automatic
            @test fd.cbar[].labelpadding[] == Float64(Constants.CBARLABEL_PADDING)

            # Act & Assert: "auto" takes the variable label, the same
            # string the title shows, and keeps following the variable
            Plotting.set_cbarlabel!(fd, "auto")
            @test fd.cbar[].label[] == "2d_float"
            @test fd.cbar[].label[] == fd.title_text[]
            state.variable[] = "int_var"
            @test fd.cbar[].label[] == "int_var"
            state.variable[] = "2d_float"

            # Act & Assert: a literal string is drawn as given
            Plotting.set_cbarlabel!(fd, "Temperature")
            @test fd.cbar[].label[] == "Temperature"

            # Act & Assert: the label survives a redraw, a plot type
            # change and switching the colorbar off and on again
            Plotting.redraw!(fd)
            @test fd.cbar[].label[] == "Temperature"
            state.plot_type_name[] = "contourf"
            Plotting.create_axis!(fd, state)
            @test fd.cbar[].label[] == "Temperature"
            Plotting.set_colorbar!(fd, false)
            Plotting.set_colorbar!(fd, true)
            @test fd.cbar[].label[] == "Temperature"

            # Act & Assert: both spellings of "off" clear the label
            Plotting.set_cbarlabel!(fd, false)
            @test fd.cbar[].label[] == ""
            Plotting.set_cbarlabel!(fd, "auto")
            Plotting.set_cbarlabel!(fd, "")
            @test fd.cbar[].label[] == ""

            # Act & Assert: the styling reaches the live colorbar without
            # a redraw
            cbar = fd.cbar[]
            Plotting.set_cbarlabel!(fd, "Temperature")
            Plotting.set_cbarlabelsize!(fd, 30)
            Plotting.set_cbarlabelcolor!(fd, :red)
            Plotting.set_cbarlabelfont!(fd, "bold")
            Plotting.set_cbarlabelrotation!(fd, 0)
            Plotting.set_cbarlabelpadding!(fd, 15)
            @test fd.cbar[] === cbar
            @test cbar.labelsize[] == 30.0
            @test cbar.labelcolor[] == :red
            @test cbar.labelfont[] == to_font(fonts, :bold)
            @test cbar.labelrotation[] == 0.0
            @test cbar.labelpadding[] == 15.0
            # a font the theme does not name is loaded by family name
            Plotting.set_cbarlabelfont!(fd, "TeX Gyre Heros Makie")
            @test cbar.labelfont[] == to_font("TeX Gyre Heros Makie")
            # nothing hands the orientation back to Makie
            Plotting.set_cbarlabelrotation!(fd, nothing)
            @test cbar.labelrotation[] === Makie.automatic

            # Act - set everything through the keyword path instead
            kwarg_text[] = ("cbarlabel=\"Salinity\", cbarlabelsize=18, " *
                            "cbarlabelcolor=:blue, cbarlabelfont=\"italic\", " *
                            "cbarlabelrotation=1.5, cbarlabelpadding=8")
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished

            # Assert
            @test fd.cbar[].label[] == "Salinity"
            @test fd.cbar[].labelsize[] == 18.0
            @test fd.cbar[].labelcolor[] == :blue
            @test fd.cbar[].labelfont[] == to_font(fonts, :italic)
            @test fd.cbar[].labelrotation[] == 1.5
            @test fd.cbar[].labelpadding[] == 8.0

            # Act - deleting the keywords restores the defaults
            kwarg_text[] = ""
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished

            # Assert
            @test settings.cbarlabel[] === nothing
            @test fd.cbar[].label[] == ""
            @test fd.cbar[].labelsize[] == Float64(Constants.LABELSIZE)
            @test fd.cbar[].labelcolor[] == Constants.CBARLABEL_COLOR
            @test fd.cbar[].labelfont[] == to_font(fonts, :regular)
            @test fd.cbar[].labelrotation[] === Makie.automatic
            @test fd.cbar[].labelpadding[] == Float64(Constants.CBARLABEL_PADDING)

            # Cleanup
            cleanup(dataset)
        end

        @testset "cbarlabel without a colorbar" begin
            # Arrange - a plot type that has no colorbar at all
            fd, state, dataset = arrange_and_create_axis(
                "2d_float", ["lon"], "line")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
            @test fd.cbar[] === nothing

            # Act & Assert: the settings are stored silently -- a warning
            # here would make the kwargs path revert them
            @test_nowarn begin
                kwarg_text[] = "cbarlabel=\"auto\", cbarlabelsize=26"
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            end
            @test fd.settings.cbarlabel[] == "auto"
            @test fd.settings.cbarlabelsize[] == 26.0

            # Act - switch to a plot type that does have a colorbar
            state.y_name[] = "lat"
            state.plot_type_name[] = "heatmap"
            Plotting.create_axis!(fd, state)

            # Assert: the stored label shows up now
            @test fd.cbar[].label[] == "2d_float"
            @test fd.cbar[].labelsize[] == 26.0

            # Cleanup
            cleanup(dataset)
        end

        @testset "moveable" begin
            # Arrange
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Assert Check that the axis is moveable by default
            @test fd.ax[] isa Axis
            @test fd.ax[].interactions[:dragpan][1]

            # Act - make axis non-moveable via kwarg
            kwarg_text[] = "moveable = false"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test !fd.ax[].interactions[:dragpan][1]

            # Act - make axis moveable again via kwarg
            kwarg_text[] = "moveable = true"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.ax[].interactions[:dragpan][1]

            # Act - set to non-Bool value
            @test_warn "Value for moveable must be of type" begin
                kwarg_text[] = "moveable = 123"
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            end

            # Act - Disable moveable and then delete kwarg
            kwarg_text[] = "moveable = false"
            kwarg_text[] = ""
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are
            @test fd.ax[].interactions[:dragpan][1]

            # Cleanup
            cleanup(dataset)
        end

        @testset "geographic" begin
            @testset "Geographic available" begin
                # Arrange
                fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
                kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

                # Assert Check that the axis is not geographic by default
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] isa Lines

                # Act - make axis geographic 
                kwarg_text[] = "geographic = true"

                # Assert
                @test fd.ax[] isa GeoAxis
                @test Plotting.primary(fd) isa Surface
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] isa Lines

                # Act - disable geographic via kwarg
                kwarg_text[] = "geographic = false"
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                # Assert
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] isa Lines

                # Cleanup
                cleanup(dataset)
            end

            @testset "Geographic unavailable" begin
                # Arrange
                fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "float_dim"], "heatmap")
                kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

                # Assert Check that the axis is not geographic by default
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] === nothing

                # Act - make axis geographic 
                kwarg_text[] = "geographic = true"

                # Assert
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] === nothing

                # Act - disable geographic via kwarg
                kwarg_text[] = "geographic = false"
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                # Assert
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] === nothing

                # Cleanup
                cleanup(dataset)
            end
        end

        @testset "Projection" begin
            @testset "Projection available" begin
                for proj in [
                    "+proj=ortho",
                    "+proj=wintri",
                    "+proj=natearth2",
                    "+proj=merc",
                    "+proj=bertin1953"]
                    @testset "Projection: $proj" begin
                        # Arrange
                        fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
                        kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

                        # Assert Check that the axis is not geographic by default
                        @test fd.ax[] isa Axis

                        # Act - set projection via kwarg
                        kwarg_text[] = "proj=\"$proj\""
                        [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                        # Assert: Axis should now be a GeoAxis with the specified projection
                        @test fd.settings.proj[] == proj
                        @test fd.ax[] isa GeoAxis
                        @test Plotting.primary(fd) isa Surface
                        @test fd.cbar[] isa Colorbar
                        @test fd.earth[] === nothing
                        @test fd.land[] === nothing
                        @test fd.coastlines[] isa Lines
                        @test fd.ax[].dest[] == proj

                        # Cleanup
                        cleanup(dataset)
                    end
                end
            end

            @testset "Projection unavailable" begin
                # Arrange
                fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "float_dim"], "heatmap")
                kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

                # Assert Check that the axis is not geographic by default
                @test fd.ax[] isa Axis

                # Act - set projection via kwarg
                kwarg_text[] = "proj=\"+proj=ortho\""
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                # Assert: Axis should still be a regular Axis
                @test fd.settings.proj[] == "+proj=ortho"
                @test fd.ax[] isa Axis
                @test Plotting.primary(fd) isa Heatmap
                @test fd.cbar[] isa Colorbar
                @test fd.earth[] === nothing
                @test fd.land[] === nothing
                @test fd.coastlines[] === nothing

                # Cleanup
                cleanup(dataset)
            end
        end

        @testset "Coastlines, Land and Earth" begin
            for geo in [true, false]
                @testset "geographic = $geo" begin
                    # Arrange
                    fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
                    kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
                    kwarg_text[] = "geographic = $geo"
                    ax_type = geo ? GeoAxis : Axis
                    earth_type = geo ? Surface : Image

                    # Assert Check that coastlines are present by default, but not land or earth
                    @test fd.ax[] isa ax_type
                    @test fd.coastlines[] isa Lines
                    @test fd.land[] === nothing
                    @test fd.earth[] === nothing

                    # Act - add land via kwarg
                    kwarg_text[] = "land = true, geographic = $geo"
                    [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                    # Assert
                    @test fd.ax[] isa ax_type
                    @test fd.coastlines[] isa Lines
                    @test fd.land[] isa Poly
                    @test fd.earth[] === nothing

                    # Act - add earth via kwarg
                    kwarg_text[] = "earth = true, geographic = $geo"
                    [wait(t) for t in fd.tasks[]]  # wait until all tasks are

                    # Assert
                    @test fd.ax[] isa ax_type
                    @test fd.coastlines[] isa Lines
                    @test fd.land[] === nothing
                    @test fd.earth[] isa earth_type

                    # Act - earth + land
                    kwarg_text[] = "land = true, earth = true, geographic = $geo"
                    [wait(t) for t in fd.tasks[]]  # wait until all tasks are
                    @test fd.ax[] isa ax_type
                    @test fd.coastlines[] isa Lines
                    @test fd.land[] isa Poly
                    @test fd.earth[] isa earth_type

                    # Cleanup
                    cleanup(dataset)
                end
            end
        end

        @testset "Scale" begin
            fd, state, dataset = arrange_and_create_axis("5d_float", ["lon", "lat"], "heatmap")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

            # Assert default scale
            @test fd.settings.scale[] == 110
            @test fd.coastlines[] isa Lines

            # Act
            kwarg_text[] = "scale = 50"

            # Assert
            @test fd.settings.scale[] == 50
            @test fd.coastlines[] isa Lines

            # Act - change scale via kwarg
            kwarg_text[] = "scale = 10"
            [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished

            # Assert
            @test fd.settings.scale[] == 10
            @test fd.coastlines[] isa Lines

            # Act - change scale to bad value
            @test_warn "Available scales are" begin
                kwarg_text[] = "scale = 77"  # not an available scale
                [wait(t) for t in fd.tasks[]]  # wait until all tasks are finished
            end

            # Assert - scale should not have changed
            @test fd.settings.scale[] == 10
            @test fd.coastlines[] isa Lines

            # Cleanup
            cleanup(dataset)
        end
    end

    # ============================================
    #  Unit Tests
    # ============================================

    @testset "Unit Tests" begin
        @testset "kwarg_dict_to_string" begin
            # Arrange
            d = OrderedDict(:a => 1,
                     :b => 2.5,
                     :c => "test",
                     :d => :symbol,
                     :e => [1, 2, 3],
                     :f => (1, 2),
                     :g => 1:5,
                     :h => nothing,
                     )

            # Act
            s = Plotting.kwarg_dict_to_string(d)

            # Assert
            @test occursin("a=1", s)
            @test occursin("b=2.5", s)
            @test occursin("c=\"test\"", s)
            @test occursin("d=:symbol", s)
            @test occursin("e=[1, 2, 3]", s)
            @test occursin("f=(1, 2)", s)
            @test occursin("g=1:5", s)
            @test occursin("h=nothing", s)
            @test Plotting.kwarg_dict_to_string(OrderedDict{Symbol, Any}()) == ""
        end

        @testset "resolve_cbarlabel" begin
            # off: unset, explicitly false, or an empty string
            @test Plotting.resolve_cbarlabel(nothing, "Temp") == ""
            @test Plotting.resolve_cbarlabel(false, "Temp") == ""
            @test Plotting.resolve_cbarlabel("", "Temp") == ""
            # the variable's own label
            @test Plotting.resolve_cbarlabel("auto", "Temp") == "Temp"
            @test Plotting.resolve_cbarlabel(true, "Temp") == "Temp"
            # anything else is literal
            @test Plotting.resolve_cbarlabel("Salinity", "Temp") == "Salinity"
        end
    end

    # ============================================
    #  Vector plots
    # ============================================

    @testset "Vector plots" begin
        VECTOR_TYPES = ("quiver", "streamplot")

        # arrows keep the range in Float64, a heatmap converts it to a
        # Vec2f, so compare the numbers rather than their storage type
        crange(fd) = Float64.(Tuple(Plotting.primary(fd).colorrange[]))
        approx(a, b) = all(isapprox.(a, b; rtol = 1e-6))

        function init_vector_figure(plot_type::String = "quiver";
                                    variable::String = "u",
                                    partner::String = "v",
                                    geographic::Bool = false)
            dataset = make_vector_temp_dataset()
            ui = UI.UIElements(dataset)
            plot_data = Plotting.PlotData(ui.state, dataset)
            fd = Plotting.FigureData(plot_data, ui)
            state = ui.state
            state.variable[] = variable
            state.variable2[] = partner
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = Constants.NOT_SELECTED_LABEL
            fd.settings.geographic[] = geographic
            state.plot_type_name[] = plot_type
            Plotting.create_axis!(fd, state)
            (fd, state, dataset)
        end

        @testset "Registry" begin
            for name in VECTOR_TYPES
                plot = Plotting.PLOT_TYPES[name]
                @test plot.ndims == 2
                @test plot.colorbar
                @test plot.nfields == 2
                @test plot.make_axis === Plotting.create_2d_axis
                @test name ∈ Constants.GEOGRAPHIC_PLOT_TYPES
                @test name ∈ Plotting.get_plot_options(2)
                @test name ∉ Plotting.get_plot_options(1)
            end
            # every other type still draws a single component
            for (name, plot) in Plotting.PLOT_TYPES
                name ∈ VECTOR_TYPES && continue
                @test plot.nfields == 1
            end
            # the 2D defaults are untouched
            @test Plotting.get_dimension_plot(2) == "heatmap"
            @test Plotting.get_fallback_plot(2) == "heatmap"
        end

        @testset "Decimation indices" begin
            dec = Plotting.decimation_indices
            # a target count, so the sample count follows the target and
            # not the grid: both grids land on ~24 columns
            @test length(dec(72, 24, nothing)) == 24
            @test length(dec(360, 24, nothing)) == 24
            @test length(dec(1000, 24, nothing)) == 24
            # never more samples than grid points
            @test dec(5, 24, nothing) == 1:1:5
            @test dec(1, 24, nothing) == 1:1:1
            # `every` picks exact grid points and overrides the target
            @test dec(72, 24, 6) == 1:6:72
            @test length(dec(72, 24, 6)) == 12
            @test dec(72, 24, 1) == 1:1:72
            # degenerate inputs stay empty rather than throwing
            @test isempty(dec(0, 24, nothing))
        end

        @testset "Robust length scale" begin
            q = Plotting.finite_quantile
            @test q([1.0, 2.0, 3.0, 4.0], 1.0) == 4.0
            @test q([1.0, 2.0, 3.0, 4.0], 0.5) == 2.0
            @test q(Float64[], 0.98) == 0.0
            @test q([1.0, NaN, 2.0, Inf], 1.0) == 2.0

            # one outlier must not shrink the field: the scale comes from
            # the 98th percentile, not the maximum
            x = collect(0.0:1.0:99.0)
            y = collect(0.0:1.0:9.0)
            u = ones(100, 10)
            u[50, 5] = 1000.0
            field = Plotting.decimate_vector_field(
                x, y, u, zeros(100, 10), (100, 10), nothing, false)
            @test field.lengthscale ≈ 0.9 * 1.0 / 1.0
            @test maximum(field.magnitude) == 1000.0
        end

        @testset "Decimated field" begin
            x = collect(1.0:12.0)
            y = collect(1.0:8.0)
            u = [Float64(i) for i in 1:12, j in 1:8]
            v = [Float64(j) for i in 1:12, j in 1:8]

            field = Plotting.decimate_vector_field(
                x, y, u, v, (4, 4), nothing, false)
            @test length(field.x) == 4
            @test length(field.y) == 4
            @test size(field.u) == (4, 4)
            # the magnitudes line up element for element with vec(u)
            @test field.magnitude == vec(hypot.(field.u, field.v))
            @test length(field.magnitude) == 16

            # `every` overrides the target
            field = Plotting.decimate_vector_field(
                x, y, u, v, (4, 4), 2, false)
            @test field.x == x[1:2:12]
            @test field.y == y[1:2:8]

            # the guard: x, y and the data arrive in separate notifications
            @test Plotting.decimate_vector_field(
                x, y, nothing, v, (4, 4), nothing, false) ===
                Plotting.EMPTY_VECTOR_FIELD
            @test Plotting.decimate_vector_field(
                x, collect(1.0:9.0), u, v, (4, 4), nothing, false) ===
                Plotting.EMPTY_VECTOR_FIELD
            @test Plotting.decimate_vector_field(
                [1.0], [1.0], ones(1, 1), ones(1, 1), (4, 4), nothing, false) ===
                Plotting.EMPTY_VECTOR_FIELD
        end

        @testset "Geographic corrections" begin
            lon = collect(-180.0:30.0:150.0)
            lat = [0.0, 60.0]
            u = ones(length(lon), 2)
            v = zeros(length(lon), 2)

            # a plain axis draws the components as they are
            plain = Plotting.decimate_vector_field(
                lon, lat, u, v, (100, 100), nothing, false)
            @test all(plain.u .== 1.0)

            # on a map the zonal component is spread over the longitude
            # degrees it actually covers
            geo = Plotting.decimate_vector_field(
                lon, lat, u, v, (100, 100), nothing, true)
            @test geo.u[1, 1] ≈ 1.0                  # equator: no change
            @test geo.u[1, 2] ≈ 1.0 / cosd(60.0)     # 60 N: stretched
            # ... but the colors stay the physical magnitudes
            @test all(geo.magnitude .== 1.0)

            # the floor keeps the pole finite
            polar = Plotting.decimate_vector_field(
                lon, [0.0, 89.999], u, v, (100, 100), nothing, true)
            @test polar.u[1, 2] ≈ 1.0 / Constants.COS_LATITUDE_FLOOR
        end

        @testset "Global domains only" begin
            wraps = Plotting.wraps_globally
            # a global grid stops one cell short of a full turn, so the
            # span alone would call a coarse one regional
            @test wraps(collect(-180.0:30.0:150.0))      # span 330, 30 cells
            @test wraps(collect(range(-180.0, 175.0, 72)))
            @test wraps(collect(range(-179.75, 179.75, 720)))
            @test wraps(collect(0.0:10.0:350.0))         # 0..360 grid
            @test wraps([-180.0, 175.0])
            # regional cut-outs are not
            @test !wraps(collect(20.0:10.0:70.0))
            @test !wraps(collect(range(-30.0, 40.0, 64)))
            @test !wraps([0.0])
            @test !wraps(Float64[])

            # ... and the mask follows: the same eastward field keeps its
            # edge arrows on a regional grid and loses them on a global one
            edge_arrows(lon) = Plotting.decimate_vector_field(
                lon, [0.0, 10.0], ones(length(lon), 2), zeros(length(lon), 2),
                (100, 100), nothing, true).u[end, :]
            @test all(isnan, edge_arrows(collect(-180.0:30.0:150.0)))
            @test all(isfinite, edge_arrows(collect(20.0:10.0:70.0)))
        end

        @testset "Dateline mask" begin
            mask! = Plotting.mask_outside_domain!
            # an arrow whose tip stays inside is kept
            u = fill(1.0, 1, 1)
            v = zeros(1, 1)
            mask!([0.0], [0.0], u, v, 1.0, (-180.0, 180.0), (-90.0, 90.0))
            @test u[1, 1] == 1.0

            # one whose tip crosses the seam is dropped: projected, it
            # would be thrown onto the opposite map edge
            u = fill(20.0, 1, 1)
            v = zeros(1, 1)
            mask!([170.0], [0.0], u, v, 1.0, (-180.0, 180.0), (-90.0, 90.0))
            @test isnan(u[1, 1]) && isnan(v[1, 1])

            # the same past the poles
            u = zeros(1, 1)
            v = fill(20.0, 1, 1)
            mask!([0.0], [80.0], u, v, 1.0, (-180.0, 180.0), (-90.0, 90.0))
            @test isnan(u[1, 1]) && isnan(v[1, 1])

            # the domain comes from the data, so a 0..360 grid wraps at 360
            u = fill(20.0, 1, 1)
            v = zeros(1, 1)
            mask!([350.0], [0.0], u, v, 1.0, (0.0, 360.0), (-90.0, 90.0))
            @test isnan(u[1, 1])

            # and the whole geographic path applies it: a steady eastward
            # wind reaches past the eastern edge only from the last column
            lon = collect(-180.0:30.0:150.0)
            field = Plotting.decimate_vector_field(
                lon, [0.0, 10.0], ones(length(lon), 2), zeros(length(lon), 2),
                (100, 100), nothing, true)
            @test all(isnan, field.u[end, :])
            @test all(isfinite, field.u[1:(end - 1), :])
            # the colors are computed before the mask, so they survive
            @test all(isfinite, field.magnitude)
        end

        @testset "Labels name both components" begin
            (fd, state, dataset) = init_vector_figure("quiver")
            labels = fd.plot_data.labels

            # the title names the field, the colorbar the scalar its
            # colors stand for -- and the shared unit appears once
            @test labels.title[] == "Eastward wind / Northward wind [m s-1]"
            @test labels.cbar[] == "|(u, v)| [m s-1]"
            @test fd.title_text[] == labels.title[]
            @test fd.cbar_label.text[] == ""   # no label until asked for
            Plotting.update_kwargs!(
                fd, OrderedDict{Symbol, Any}(:cbarlabel => "auto"))
            @test fd.cbar_label.text[] == "|(u, v)| [m s-1]"

            # a component without a long_name falls back to its name, and
            # units that disagree are dropped rather than misreported
            state.variable2[] = "temp"
            @test labels.title[] == "Eastward wind / temp"
            @test labels.cbar[] == "|(u, temp)|"

            # a dimensionless unit prints nothing at all, as everywhere
            state.variable[] = "ufrac"
            state.variable2[] = "vfrac"
            @test labels.title[] == "Zonal fraction / Meridional fraction"
            @test labels.cbar[] == "|(ufrac, vfrac)|"

            # an explicit override still wins over both
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                :title => "Winds", :cbarlabel => "Speed"))
            @test fd.title_text[] == "Winds"
            @test fd.cbar_label.text[] == "Speed"
            cleanup(dataset)
        end

        @testset "Scalar labels are unchanged" begin
            (fd, state, dataset) = init_vector_figure("heatmap")
            labels = fd.plot_data.labels
            # with one component both labels are the variable's own, byte
            # for byte what Data.get_label returns
            expected = Data.get_label(dataset, "u")
            @test labels.title[] == expected
            @test labels.cbar[] == expected
            @test expected == "Eastward wind [m s-1]"

            # ... and a partner sitting in the second dropdown, left over
            # from a vector type, changes nothing
            state.variable2[] = "temp"
            @test labels.title[] == expected
            @test labels.cbar[] == expected
            cleanup(dataset)
        end

        @testset "Partner data" begin
            dataset = make_vector_temp_dataset()
            ui = UI.UIElements(dataset)
            state = ui.state
            plot_data = Plotting.PlotData(state, dataset)
            state.variable[] = "u"
            state.x_name[] = "lon"
            state.y_name[] = "lat"

            # a scalar type never reads a second component
            state.plot_type_name[] = "heatmap"
            state.variable2[] = "v"
            @test plot_data.d[1][1][2][] !== nothing
            @test plot_data.d[1][2][2][] === nothing

            # a vector type does
            state.plot_type_name[] = "quiver"
            @test size(plot_data.d[1][2][2][]) == size(plot_data.d[1][1][2][])
            @test plot_data.d[1][2][2][] == dataset.ds["v"][:, :, 1]

            # a partner over the wrong dimensions yields nothing
            state.variable2[] = "vmix"
            @test plot_data.d[1][2][2][] === nothing

            # and so does no partner at all
            state.variable2[] = Constants.NOT_SELECTED_LABEL
            @test plot_data.d[1][2][2][] === nothing

            cleanup(dataset)
        end

        @testset "Plot objects" begin
            (fd, state, dataset) = init_vector_figure("quiver")
            @test fd.ax[] isa Axis
            @test Plotting.primary(fd) isa Makie.Arrows2D
            @test fd.cbar[] isa Colorbar
            # 12x8 grid thinned to the default (24, 16) target: nothing
            # to thin, so every grid point is drawn
            @test length(Plotting.primary(fd).points[]) == 12 * 8
            cleanup(dataset)

            (fd, state, dataset) = init_vector_figure("streamplot")
            @test Plotting.primary(fd) isa Makie.StreamPlot
            @test fd.cbar[] isa Colorbar
            # the step is derived from the domain, not Makie's 0.01
            @test Plotting.primary(fd).stepsize[] ≈ 140.0 / Constants.STREAMPLOT_STEPS
            cleanup(dataset)

            # both types survive a geographic axis
            for name in VECTOR_TYPES
                (fd, state, dataset) = init_vector_figure(
                    name, geographic = true)
                @test fd.ax[] isa GeoAxis
                @test Plotting.primary(fd) !== nothing
                cleanup(dataset)
            end
        end

        @testset "Density settings" begin
            (fd, state, dataset) = init_vector_figure("quiver")
            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string

            @test fd.settings.arrows[] == Constants.VECTOR_ARROWS
            @test fd.settings.every[] === nothing

            # a target count thins the grid without rebuilding the axis
            axis = fd.ax[]
            kwarg_text[] = "arrows=(6, 4)"
            @test fd.settings.arrows[] == (6, 4)
            @test length(Plotting.primary(fd).points[]) == 6 * 4
            @test fd.ax[] === axis

            # `every` picks exact grid points
            kwarg_text[] = "every=3"
            @test fd.settings.every[] == 3
            @test length(Plotting.primary(fd).points[]) == 4 * 3

            # and deleting both restores the defaults
            kwarg_text[] = ""
            @test fd.settings.arrows[] == Constants.VECTOR_ARROWS
            @test fd.settings.every[] === nothing
            @test length(Plotting.primary(fd).points[]) == 12 * 8

            # bad values are rejected and change nothing
            @test_logs (:error,) match_mode = :any begin
                Plotting.set_arrows!(fd, (0, 4))
            end
            @test fd.settings.arrows[] == Constants.VECTOR_ARROWS
            @test_logs (:error,) match_mode = :any begin
                Plotting.set_every!(fd, 0)
            end
            @test fd.settings.every[] === nothing
            cleanup(dataset)
        end

        @testset "Streamlines ignore the arrow density" begin
            # streamlines follow the field instead of sampling it, so the
            # density settings are stored but must not cost an integration
            (fd, state, dataset) = init_vector_figure("streamplot")
            @test !Plotting.is_arrow_type(fd)
            before = Plotting.primary(fd).line_points[]

            kwarg_text = fd.ui.main_menu.plot_menu.plot_kw.stored_string
            kwarg_text[] = "arrows=(6, 4), every=3"

            @test fd.settings.arrows[] == (6, 4)
            @test fd.settings.every[] == 3
            @test Plotting.primary(fd).line_points[] === before
            cleanup(dataset)
        end

        @testset "Density settings without arrows" begin
            # a scalar plot stores the value silently: a warning here
            # would trip the kwargs path's revert-on-stderr machinery
            (fd, state, dataset) = arrange_and_create_axis(
                "2d_float", ["lon", "lat"], "heatmap")
            output = @capture_err begin
                Plotting.set_arrows!(fd, (10, 8))
                Plotting.set_every!(fd, 2)
            end
            @test isempty(output)
            @test fd.settings.arrows[] == (10, 8)
            @test fd.settings.every[] == 2
            cleanup(dataset)
        end

        @testset "Magnitude color range" begin
            wait_scan(fd) = let t = fd.layers[1].crange_scan.task
                t === nothing || wait(t)
            end
            (fd, state, dataset) = init_vector_figure("quiver")
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            wait_scan(fd)

            # the key names both components, so the scan reads both
            key = Plotting.colorrange_key(fd, :cycle)
            @test key[1] == ("u", "v")

            expected = vector_magnitude_range(dataset)
            @test approx(crange(fd), expected)

            # the signed u range is emphatically not what got pinned
            urange = extrema(dataset.ds["u"][:, :, :])
            @test urange[1] < 0 < expected[1]
            @test !approx(crange(fd), urange)

            # and it holds still across the playback cycle
            for idx in 1:length(VECTOR_TIME)
                fd.ui.main_menu.coord_sliders.sliders["time"].value[] = idx
                wait_scan(fd)
                @test approx(crange(fd), expected)
            end

            # every drawn magnitude fits inside the pin
            drawn = Plotting.primary(fd).color[]
            @test minimum(drawn) >= expected[1] - 1e-9
            @test maximum(drawn) <= expected[2] + 1e-9

            # arrows carry no levels, so the contour pin stays inert
            @test !Plotting.is_contour_type(fd)
            @test :levels ∉ propertynames(Plotting.primary(fd))
            @test fd.layers[1].crange_scan.base_levels === nothing
            cleanup(dataset)
        end

        @testset "Single-variable types are unaffected" begin
            wait_scan(fd) = let t = fd.layers[1].crange_scan.task
                t === nothing || wait(t)
            end
            # the same dataset drawn as a heatmap still pins the signed
            # range of the one variable it shows
            (fd, state, dataset) = init_vector_figure("heatmap")
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            wait_scan(fd)
            key = Plotting.colorrange_key(fd, :cycle)
            @test key[1] == ("u",)
            urange = extrema(dataset.ds["u"][:, :, :])
            @test approx(crange(fd), urange)
            cleanup(dataset)
        end
    end

    # ============================================
    #  Overlaid layers
    # ============================================

    @testset "Overlaid layers" begin

        "A two-layer figure on the vector fixture: `u` under, `temp` over."
        function init_overlay_figure(; base::String = "heatmap",
                                     over::String = "temp",
                                     over_type::String = "contour",
                                     geographic::Bool = false)
            dataset = make_vector_temp_dataset()
            ui = UI.UIElements(dataset)
            plot_data = Plotting.PlotData(ui.state, dataset)
            fd = Plotting.FigureData(plot_data, ui)
            state = ui.state
            state.variable[] = "u"
            state.x_name[] = "lon"
            state.y_name[] = "lat"
            state.z_name[] = Constants.NOT_SELECTED_LABEL
            fd.settings.geographic[] = geographic
            state.plot_type_name[] = base
            Plotting.create_axis!(fd, state)
            Plotting.set_layer_variables!(fd, 2, [over])
            Plotting.set_layer_plot_type!(fd, 2, over_type)
            (fd, state, dataset)
        end

        @testset "Layer naming" begin
            @test Plotting.layer_prefix.(1:4) == ["base", "over", "over2", "over3"]
            @test Plotting.layer_index("base") == 1
            @test Plotting.layer_index("over") == 2
            @test Plotting.layer_index("over2") == 3
            @test Plotting.layer_index("over17") == 18
            # names that address no layer at all
            @test Plotting.layer_index("over0") === nothing
            @test Plotting.layer_index("overs") === nothing
            @test Plotting.layer_index("lon") === nothing
            @test Plotting.layer_index("") === nothing
        end

        @testset "Splitting a prefixed keyword" begin
            split = Plotting.split_layer_key
            @test split(Symbol("over.levels")) == (2, :levels)
            @test split(Symbol("base.colormap")) == (1, :colormap)
            @test split(Symbol("over3.color")) == (4, :color)
            # a dot the prefix does not claim keeps the key whole
            @test split(:colormap) === nothing
            @test split(Symbol("lon.min")) === nothing
            @test split(Symbol("over.")) === nothing
            @test split(Symbol(".levels")) === nothing
        end

        @testset "Compatible plot types" begin
            fits(a, b) = Plotting.fits_layer(
                Plotting.PLOT_TYPES[a], Plotting.PLOT_TYPES[b])
            # the four groups: a layer may only join the base's own
            @test fits("heatmap", "contour")
            @test fits("contourf", "quiver")
            @test fits("surface", "wireframe")
            @test fits("line", "scatter")
            @test fits("volume", "contour3d")
            # ... across groups it may not, even at equal ndims
            @test !fits("heatmap", "surface")
            @test !fits("surface", "contour")
            @test !fits("heatmap", "line")
            @test !fits("volume", "heatmap")
            # and nothing at all overlays "no plot selected"
            @test !fits(Constants.NOT_SELECTED_LABEL, "heatmap")

            options = Plotting.overlay_plot_options(Plotting.PLOT_TYPES["heatmap"])
            @test Set(options) == Set(["heatmap", "contour", "contourf",
                                       "quiver", "streamplot"])
            # over a flat base a second heatmap would hide the first
            @test Plotting.default_overlay_plot(
                Plotting.PLOT_TYPES["heatmap"], 1) == "contour"
            # two variables name a vector layer
            @test Plotting.default_overlay_plot(
                Plotting.PLOT_TYPES["heatmap"], 2) == "quiver"
            # elsewhere the base's own type is the only sensible start
            @test Plotting.default_overlay_plot(
                Plotting.PLOT_TYPES["surface"], 1) == "surface"
            @test Plotting.default_overlay_plot(
                Plotting.PLOT_TYPES["line"], 1) == "line"
        end

        @testset "Adding and removing" begin
            (fd, state, dataset) = init_overlay_figure()
            @test Plotting.layer_count(fd) == 2
            @test Plotting.primary(fd) isa Heatmap
            @test fd.layers[2].plot_obj[] isa Contour
            @test Plotting.layer_variables(fd, 2) == ["temp"]
            # both plots sit on the same axis, and only the base gets a bar
            @test Plotting.primary(fd) ∈ fd.ax[].scene.plots
            @test fd.layers[2].plot_obj[] ∈ fd.ax[].scene.plots
            @test fd.cbar[] isa Colorbar

            # a third layer, and a vector layer at that
            Plotting.set_layer_variables!(fd, 3, ["u", "v"])
            Plotting.set_layer_plot_type!(fd, 3, "quiver")
            @test Plotting.layer_count(fd) == 3
            @test fd.layers[3].plot_obj[] isa Makie.Arrows2D
            @test Plotting.layer_variables(fd, 3) == ["u", "v"]

            # removing the middle one renumbers the rest
            Plotting.remove_layer!(fd, 2)
            @test Plotting.layer_count(fd) == 2
            @test Plotting.layer_variables(fd, 2) == ["u", "v"]
            @test fd.layers[2].plot_obj[] isa Makie.Arrows2D

            Plotting.remove_layer!(fd, 2)
            @test Plotting.layer_count(fd) == 1
            @test Plotting.primary(fd) isa Heatmap
            cleanup(dataset)
        end

        @testset "Refusing what cannot be drawn" begin
            (fd, state, dataset) = init_overlay_figure()
            # the base is never addressed through the layer commands
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.set_layer_variables!(fd, 1, ["temp"]) == ""
            end
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.remove_layer!(fd, 1) == ""
            end
            # a variable that is not there
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.set_layer_variables!(fd, 3, ["nope"]) == ""
            end
            # a layer beyond the next one up
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.set_layer_variables!(fd, 4, ["temp"]) == ""
            end
            # a plot type the base cannot share an axis with
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.set_layer_plot_type!(fd, 2, "surface") == ""
            end
            @test Plotting.layer_count(fd) == 2
            @test Plotting.layer_plot(fd, 2).type == "contour"
            cleanup(dataset)
        end

        @testset "A variable must span the drawn axes" begin
            (fd, state, dataset) = init_overlay_figure()
            # `uodd` is lon/lat only, so it fits these axes ...
            @test Plotting.layer_fits_axes(fd.plot_data, "uodd")
            @test Plotting.set_layer_variables!(fd, 3, ["uodd"]) != ""
            @test Plotting.layer_count(fd) == 3

            # ... and stops fitting once the axes move to lon/time
            state.y_name[] = "time"
            @test !Plotting.layer_fits_axes(fd.plot_data, "uodd")
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.prune_layers!(fd)
            end
            @test Plotting.layer_count(fd) == 2
            @test Plotting.layer_variables(fd, 2) == ["temp"]
            cleanup(dataset)
        end

        @testset "A changed base drops what no longer fits" begin
            (fd, state, dataset) = init_overlay_figure()
            # a one-dimensional base leaves the contour nothing to sit on
            state.plot_type_name[] = "line"
            @test_logs (:warn,) match_mode = :any begin
                @test Plotting.prune_layers!(fd)
            end
            @test Plotting.layer_count(fd) == 1
            @test !Plotting.prune_layers!(fd)  # nothing left to drop
            cleanup(dataset)
        end

        @testset "Layers survive a redraw" begin
            # a redraw swaps the axis identity; a layer rebuilt anywhere but
            # in the axis listener would stay on the deleted one and vanish
            (fd, state, dataset) = init_overlay_figure()
            old_axis = fd.ax[]
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                :geographic => true))
            @test fd.ax[] !== old_axis
            @test fd.ax[] isa GeoAxis
            @test Plotting.layer_count(fd) == 2
            for layer in fd.layers
                @test layer.plot_obj[] !== nothing
                @test layer.plot_obj[] ∈ fd.ax[].scene.plots
            end
            cleanup(dataset)
        end

        @testset "Title" begin
            (fd, state, dataset) = init_overlay_figure()
            # several layers: names joined, units left off
            @test fd.plot_data.labels.title[] == "Eastward wind / temp"
            # a vector layer contributes the magnitude it colors by
            Plotting.set_layer_variables!(fd, 3, ["u", "v"])
            Plotting.set_layer_plot_type!(fd, 3, "quiver")
            @test fd.plot_data.labels.title[] ==
                "Eastward wind / temp / |(u, v)|"
            # and with a single layer the title is the old one, byte for byte
            Plotting.remove_layer!(fd, 3)
            Plotting.remove_layer!(fd, 2)
            @test fd.plot_data.labels.title[] == Data.get_label(dataset, "u")
            @test fd.plot_data.labels.title[] == "Eastward wind [m s-1]"
            cleanup(dataset)
        end

        @testset "Keyword routing" begin
            (fd, state, dataset) = init_overlay_figure()
            resolve(key) = Plotting.resolve_kwarg(fd, Symbol(key))

            # an unprefixed key still reaches every target owning it
            property, targets = resolve("colormap")
            @test property === :colormap
            @test Plotting.primary(fd) ∈ targets
            @test fd.layers[2].plot_obj[] ∈ targets
            @test fd.cbar[] ∈ targets
            # ... and `get` reports the first, which is the base layer
            mappings = Plotting.get_property_mappings(
                OrderedDict{Symbol, Any}(:colormap => nothing), fd)
            @test mappings[1].target_object === Plotting.primary(fd)

            # only the contour has levels
            property, targets = resolve("levels")
            @test fd.layers[2].plot_obj[] ∈ targets
            @test Plotting.primary(fd) ∉ targets

            # a prefix picks one layer out
            property, targets = resolve("over.colormap")
            @test property === :colormap
            @test targets == Any[fd.layers[2].plot_obj[]]
            property, targets = resolve("base.colormap")
            @test targets == Any[Plotting.primary(fd)]

            # the whole key wins over the prefix reading: a coordinate
            # named with a dot must keep working
            @test resolve("lon")[2] == Any[fd.range_control[]]

            # a prefix naming a layer that is not there resolves to nothing
            @test resolve("over3.colormap")[2] == Any[]
            cleanup(dataset)
        end

        @testset "Applying prefixed keywords" begin
            (fd, state, dataset) = init_overlay_figure()
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                Symbol("base.colormap") => :thermal,
                Symbol("over.color") => :black,
                Symbol("over.levels") => 4))
            @test Plotting.primary(fd).colormap[] == :thermal
            @test fd.layers[2].plot_obj[].color[] == :black
            @test fd.layers[2].plot_obj[].levels[] == 4
            # the overlay's colormap is untouched by the base's
            @test fd.layers[2].plot_obj[].colormap[] != :thermal
            cleanup(dataset)
        end

        @testset "The store keeps the key as written" begin
            # stripping the prefix would collapse `over.colormap` and
            # `colormap` onto one entry, and the revert path would write
            # one layer's value into the other's slot
            (fd, state, dataset) = init_overlay_figure()
            mappings = Plotting.get_property_mappings(
                OrderedDict{Symbol, Any}(
                    :colormap => :thermal,
                    Symbol("over.colormap") => :viridis), fd)
            keys_ = [(m.key, m.property) for m in mappings]
            @test (:colormap, :colormap) ∈ keys_
            @test (Symbol("over.colormap"), :colormap) ∈ keys_
            @test length(unique(m.key for m in mappings)) == 2
            cleanup(dataset)
        end

        @testset "Levels are counted per layer" begin
            (fd, state, dataset) = init_overlay_figure(base = "contourf")
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                :levels => 7, Symbol("over.levels") => 3))
            @test Plotting.user_levels(fd, 1) == 7
            @test Plotting.user_levels(fd, 2) == 3
            # an unprefixed one is shared, as it always was
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(:levels => 7))
            @test Plotting.user_levels(fd, 1) == 7
            @test Plotting.user_levels(fd, 2) == 7
            cleanup(dataset)
        end

        @testset "Vector density per layer" begin
            (fd, state, dataset) = init_overlay_figure(over_type = "quiver",
                                                       over = "u")
            @test Plotting.layer_plot(fd, 2).type == "quiver"
            # unset, a layer follows the figure
            @test Plotting.layer_arrows(fd, 2) == Constants.VECTOR_ARROWS
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                :arrows => (10, 8), Symbol("over.arrows") => (6, 4)))
            @test fd.settings.arrows[] == (10, 8)
            @test Plotting.layer_arrows(fd, 1) == (10, 8)
            @test Plotting.layer_arrows(fd, 2) == (6, 4)
            @test length(fd.layers[2].plot_obj[].points[]) == 6 * 4
            # deleting the override falls back to the figure's own
            Plotting.update_kwargs!(fd, OrderedDict{Symbol, Any}(
                :arrows => (10, 8)))
            @test Plotting.layer_arrows(fd, 2) == (10, 8)
            cleanup(dataset)
        end

        @testset "Colour range per layer" begin
            # a heatmap stores its range as a Vec2f: compare the numbers
            close_enough(a, b) = all(isapprox.(a, b; rtol = 1e-6))
            wait_scans(fd) = Plotting.wait_for_scans(fd)
            (fd, state, dataset) = init_overlay_figure()
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            wait_scans(fd)
            # each layer scans its own field
            @test Plotting.colorrange_key(fd, :cycle, 1)[1] == ("u",)
            @test Plotting.colorrange_key(fd, :cycle, 2)[1] == ("temp",)
            Plotting.update_colorrange!(fd; sync = true)
            @test close_enough(
                Tuple(Float64.(Plotting.primary(fd).colorrange[])),
                extrema(dataset.ds["u"][:, :, :]))
            @test close_enough(
                Tuple(Float64.(fd.layers[2].plot_obj[].colorrange[])),
                extrema(dataset.ds["temp"][:, :, :]))
            cleanup(dataset)
        end

        @testset "The scan budget is spent across layers" begin
            (fd, state, dataset) = init_overlay_figure()
            fd.ui.main_menu.playback_menu.var.selection[] = "time"
            Plotting.wait_for_scans(fd)
            elements(i) = let key = Plotting.colorrange_key(fd, :cycle, i)
                Plotting.DataLimits.hyperslab_elements(
                    dataset, collect(String, key[1]),
                    collect(Union{Colon, Int}, key[2]))
            end
            total = elements(1) + elements(2)
            @test total == 2 * elements(1)

            # a budget that one layer fits into but two together do not
            targets = Tuple{Symbol, Any}[
                (:cycle, Plotting.colorrange_key(fd, :cycle, i)) for i in 1:2]
            for layer in fd.layers
                empty!(layer.crange_scan.cache)
            end
            old = Plotting.DataLimits.AUTO_SCAN_ELEMENTS[]
            try
                Plotting.DataLimits.AUTO_SCAN_ELEMENTS[] = total - 1
                gated = @test_logs (:info,) match_mode = :any begin
                    Plotting.gate_colorrange_keys!(fd, targets)
                end
                @test all(t -> t[2] === nothing, gated)
                # ... and the hint is shown once for the figure, not per layer
                @test fd.crange_hinted[]
                Plotting.DataLimits.AUTO_SCAN_ELEMENTS[] = total
                for layer in fd.layers
                    empty!(layer.crange_scan.cache)
                end
                @test Plotting.gate_colorrange_keys!(fd, targets) == targets
            finally
                Plotting.DataLimits.AUTO_SCAN_ELEMENTS[] = old
            end
            cleanup(dataset)
        end
    end

end