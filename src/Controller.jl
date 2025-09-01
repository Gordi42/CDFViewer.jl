module Controller

using GLMakie
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting

mutable struct ViewerController
    fig::Figure
    dataset::Data.CDFDataset
    variable_menu::Menu
    plot_menu::Menu
    coord_sliders::SliderGrid
end

function build_controller(dataset::Data.CDFDataset)
    fig = UI.setup_figure()
    variable_menu, plot_menu, coord_sliders, plot_types =
        UI.build_controls(fig, dataset.variables, dataset.dimensions)

    controller = ViewerController(fig, dataset, variable_menu, plot_menu, coord_sliders)

    # TODO: add reactive wiring here (plot updates, slider callbacks, playback)

    return fig, controller
end

end # module