using ArgParse
using Revise
using Test
using GLMakie
using NearestNeighbors
using CDFViewer
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller
using CDFViewer.Parsing
using CDFViewer.ViewerREPL
using CDFViewer.Interpolate

NS = Constants.NOT_SELECTED_LABEL

include("test_setup.jl")

dataset = make_temp_dataset()
# dataset = make_semi_unstructured_temp_dataset()
dataset = make_unstructured_temp_dataset()

controller = Controller.ViewerController(dataset, headless=false);

close(controller.fig_screen[])

# fname = "/home/silvano/OneDrive/Programmieren/netCDF_Project/Rust/nci_test/data/era_data.nc"
fname = "/home/silvano/Temporary/TestData/exp.basR2B7_P1D_kin_20150101T000000Z.nc"
# fname = "/home/silvano/Temporary/TestData/nib2501_oce_P1M_2d_22000101.nc"
dataset = Data.CDFDataset([fname])
controller = Controller.ViewerController(dataset, headless=false)

controller = Controller.ViewerController(dataset, headless=false);
ec = (cmd) -> ViewerREPL.evaluate_command(ViewerREPL.REPLState(controller), cmd)
ec("p heatmap")
close(controller.fig_screen[])

# ec("menu")
ec("v to")
ec("p heatmap")
ec("aspect=1")
ec("lon=(-100,0,100)")
ec("refresh")
ec("get aspect")
ec("conf")

controller.fd.fig.scene.viewport[].widths isa Vec{2, Int}


fig = Figure()

GLMakie.closeall()

deactivate_interaction!(controller.fd.ax[], :rectanglezoom)
deactivate_interaction!(controller.fd.ax[], :dragpan)

b = Observable(1)

on(b) do v
    println(b[])
    println("b changed to $v")
end

b[] = 5


activate_interaction!(controller.fd.ax[], :rectanglezoom)

controller.fd.ax[].aspect


using GeoMakie
using GLMakie

lon = LinRange(-180, 180, 360)
lat = LinRange(-90, 90, 180)
data = [sin(deg2rad(l)) * cos(deg2rad(b)) for l in lon, b in lat]

fig = Figure()
ax = GeoAxis(fig[1, 1], dest = "+proj=longlat +datum=WGS84")
surface!(ax, lon, lat, data, colormap = :balance)

fig
propertynames(ax)




dataset = make_temp_dataset()
ds = dataset.ds
interp = Interpolate.Interpolator(ds, dataset.paired_coords)

function Base.propertynames(interp::Interpolate.Interpolator)
    coords = collect(keys(interp.group_map))
    # return the coords as symbols
    Tuple(Symbol.(coords))
end

propertynames(interp)

coords = collect(keys(interp.group_map))
# return the coords as symbols
Tuple(Symbol.(coords))

dims = ["lon"]
dim_selection = Dict("lon" => 5)

Interpolate.get_this_dim_selection(dim_selection, dims)


Dict(filter( (k, v) -> k in dims, dim_selection))

this_dim_selection = Dict(filter( (k, v) -> !(k in dims), dim_selection))


fig, ax, hm = heatmap(rand(10, 10));

hm.colormap = :invalid

fig