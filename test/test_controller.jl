using Test
using GLMakie
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller

include("test_setup.jl")

dataset = make_temp_dataset()

controller = Controller.init_controller(dataset)
display(controller.fd.fig)
Controller.setup_controller!(controller)


var_menu = controller.ui.main_menu.variable_menu
pt_menu = controller.ui.main_menu.plot_menu.plot_type
dim_menus = controller.ui.coord_menu.menus
x_menu = dim_menus[1]
y_menu = dim_menus[2]
z_menu = dim_menus[3]
state = controller.ui.state
fd = controller.fd

@test pt_menu.options[] == Plotting.PLOT_OPTIONS_1D
@test state.plot_type_name[] == "line"
@test state.x_name[] == "lon"
@test state.y_name[] == "Not Selected"
@test state.z_name[] == "Not Selected"
@test fd.plot_obj[] isa Lines
@test fd.ax[] isa Axis
@test fd.cbar[] isa Nothing

# Setup some test helpers
var_name = Observable("")
on(var_name) do v
    var_menu.i_selected[] = findfirst(==(v), var_menu.options[])
    @test state.variable[] == v
    for menu in controller.ui.coord_menu.menus
        @test menu.options[] == ["Not Selected"; get_dims(v)]
    end
end
plot_type = Observable("")
on(plot_type) do pt
    pt_menu.i_selected[] = findfirst(==(pt), pt_menu.options[])
    @test state.plot_type_name[] == pt
    if Plotting.PLOT_TYPES[pt].ax_ndims == 2
        @test fd.ax[] isa Axis
    elseif Plotting.PLOT_TYPES[pt].ax_ndims == 3
        @test fd.ax[] isa Axis3
    end
    if Plotting.PLOT_TYPES[pt].colorbar
        @test fd.cbar[] isa Colorbar
    else
        @test fd.cbar[] === nothing
    end
end
x_sel = Observable("")
on(x_sel) do sel
    x_menu.i_selected[] = findfirst(==(sel), x_menu.options[])
end
y_sel = Observable("")
on(y_sel) do sel
    y_menu.i_selected[] = findfirst(==(sel), y_menu.options[])
end
z_sel = Observable("")
on(z_sel) do sel
    z_menu.i_selected[] = findfirst(==(sel), z_menu.options[])
end

function check_dim_selection(expected::Vector{String})
    @test state.x_name[] == (length(expected) ≥ 1 ? expected[1] : "Not Selected")
    @test state.y_name[] == (length(expected) ≥ 2 ? expected[2] : "Not Selected")
    @test state.z_name[] == (length(expected) == 3 ? expected[3] : "Not Selected")
end

var_name[] = "2d_float"
@test pt_menu.options[] == Plotting.PLOT_OPTIONS_2D
plot_type[] = "heatmap"
@test fd.plot_obj[] isa Heatmap
check_dim_selection(["lon", "lat"])

var_name[] = "2d_gap"
@test pt_menu.options[] == Plotting.PLOT_OPTIONS_2D
@test fd.plot_obj[] isa Heatmap
check_dim_selection(["lon", "float_dim"])

# Set the variable to a higher dimensional variable
var_name[] = "5d_float"
@test pt_menu.options[] == Plotting.PLOT_OPTIONS_3D
@test fd.plot_obj[] isa Heatmap
check_dim_selection(["lon", "float_dim"])

# Change the plot type to a 3D plot
plot_type[] = "volume"
@test fd.plot_obj[] isa Volume
check_dim_selection(["lon", "float_dim", "lat"])

# Change back to a 2D plot
plot_type[] = "surface"
@test fd.plot_obj[] isa Surface
check_dim_selection(["lon", "float_dim"])

# Change to a 1D plot
plot_type[] = "scatter"
@test fd.plot_obj[] isa Scatter
check_dim_selection(["lon"])

# Change between 3D and 1D
plot_type[] = "volume"
plot_type[] = "line"

# Change to a lower dimensional variable
plot_type[] = "volume"
var_name[] = "2d_float"
@test pt_menu.options[] == Plotting.PLOT_OPTIONS_2D
@test fd.plot_obj[] isa Heatmap

# Change to Info plot
plot_type[] = "Info"
@test fd.ax[] === nothing
@test fd.cbar[] === nothing
@test fd.plot_obj[] === nothing
check_dim_selection(Vector{String}([]))
plot_type[] = "heatmap"

# Change to a string variable
var_name[] = "string_var"
@test pt_menu.options[] == ["Info"]
@test state.plot_type_name[] == "Info"


# Test the dimension selection
var_name[] = "5d_float"
plot_type[] = "line"


x_sel[] = "float_dim"
check_dim_selection(["float_dim"])

y_sel[] = "lon"
check_dim_selection(["float_dim", "lon"])
@test fd.plot_obj[] isa Heatmap

z_sel[] = "lat"
check_dim_selection(["float_dim", "lon", "lat"])
@test fd.plot_obj[] isa Volume

x_sel[] = "Not Selected"
check_dim_selection(["lon", "lat"])
@test fd.plot_obj[] isa Heatmap

y_sel[] = "lon"
check_dim_selection(["lon"])
@test fd.plot_obj[] isa Lines

z_sel[] = "only_long"
check_dim_selection(["lon", "only_long"])
@test fd.plot_obj[] isa Heatmap

# %%
using Colors
inactive_text_color = parse(Colorant, :lightgray)
active_text_color = parse(Colorant, :black)

inactive_slider_bar_color = RGBf(0.94, 0.94, 0.94)

function set_slider_inactive!(coord_slider::UI.CoordinateSliders, dim::String)
    coord_slider.labels[dim].color[] = inactive_text_color
    coord_slider.valuelabels[dim].color[] = inactive_text_color
    coord_slider.sliders[dim].color_active[] = inactive_text_color
    coord_slider.sliders[dim].color_active_dimmed[] = inactive_slider_bar_color
    coord_slider.sliders[dim].color_inactive[] = inactive_slider_bar_color
end

function set_slider_active!(coord_slider::UI.CoordinateSliders, dim::String)
    coord_slider.labels[dim].color[] = active_text_color
    coord_slider.valuelabels[dim].color[] = active_text_color
    coord_slider.sliders[dim].color_active[] = Makie.COLOR_ACCENT[]
    coord_slider.sliders[dim].color_active_dimmed[] = Makie.COLOR_ACCENT_DIMMED[]
    coord_slider.sliders[dim].color_inactive[] = inactive_slider_bar_color
end

function set_slider_semi_active!(coord_slider::UI.CoordinateSliders, dim::String)
    coord_slider.labels[dim].color[] = semi_active_text_color
    coord_slider.valuelabels[dim].color[] = semi_active_text_color
    coord_slider.sliders[dim].color_active[] = semi_active_text_color
    coord_slider.sliders[dim].color_active_dimmed[] = inactive_slider_bar_color
    coord_slider.sliders[dim].color_inactive[] = inactive_slider_bar_color
end

set_slider_semi_active!(controller.ui.main_menu.coord_sliders, "lat")
    
controller.ui.main_menu.coord_sliders.labels["lon"].color[] = inactive_text_color
controller.ui.main_menu.coord_sliders.valuelabels["lon"].color[] = inactive_text_color
controller.ui.main_menu.coord_sliders.sliders["lon"].color_active[] = inactive_text_color
controller.ui.main_menu.coord_sliders.sliders["lon"].color_active_dimmed[] = inactive_slider_bar_color
controller.ui.main_menu.coord_sliders.sliders["lon"].color_inactive[] = inactive_slider_bar_color

controller.ui.main_menu.coord_sliders.slider_grid

RGBAf(:red)

using Makie

rgba = Makie.to_rgba(:red)  # ergibt ColorTypes.RGBA{Float32}

using Makie

col = Makie.color(:red)             # ergibt z.B. RGB{N0f8}
rgba = RGBAf0(Makie.color(:red))    # explizit RGBA{Float32}

using Colors
parse(Colorant, :red)

Makie.COLOR_ACCENT