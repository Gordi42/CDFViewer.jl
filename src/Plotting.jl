module Plotting

using DataStructures: OrderedDict
using GLMakie

struct Plot
    type::String
    ndims::Int
    ax_ndims::Int
    colorbar::Bool
    func::Function
end

const PLOT_TYPES = OrderedDict(
    "heatmap" => Plot(
        "heatmap", 2, 2, true,
        (ax, x, y, z, d) -> heatmap!(ax, x, y, d, colormap = :balance)),
    "contour" => Plot(
        "contour", 2, 2, false,
        (ax, x, y, z, d) -> contour!(ax, x, y, d, colormap = :balance)),
    "contourf" => Plot(
        "contourf", 2, 2, true,
        (ax, x, y, z, d) -> contourf!(ax, x, y, d, colormap = :balance)),
    "surface" => Plot(
        "surface", 2, 3, true,
        (ax, x, y, z, d) -> surface!(ax, x, y, d, colormap = :balance)),
    "wireframe" => Plot(
        "wireframe", 2, 3, false,
        (ax, x, y, z, d) -> wireframe!(ax, x, y, d, color = :royalblue3)),
    "line" => Plot(
        "line", 1, 2, false,
        (ax, x, y, z, d) -> lines!(ax, x, d, color = :royalblue3)),
    "scatter" => Plot(
        "scatter", 1, 2, false,
        (ax, x, y, z, d) -> scatter!(ax, x, d, color = :royalblue3)),
    "volume" => Plot(
        "volume", 3, 3, true,
        (ax, x, y, z, d) -> volume!(ax, (x[1], x[end]), (y[1], y[end]), (z[1], z[end]), d, colormap = :balance)),
    "contour3d" => Plot(
        "contour3d", 3, 3, false,
        (ax, x, y, z, d) -> contour!(ax, (x[1], x[end]), (y[1], y[end]), (z[1], z[end]), d, colormap = :balance)),
)

const PLOT_OPTIONS_3D = collect(keys(PLOT_TYPES))
const PLOT_OPTIONS_2D = filter(k -> PLOT_TYPES[k].ndims <= 2, PLOT_OPTIONS_3D)
const PLOT_OPTIONS_1D = filter(k -> PLOT_TYPES[k].ndims == 1, PLOT_OPTIONS_3D)

end # module Plotting