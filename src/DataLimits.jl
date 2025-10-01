module DataLimits

data_limits = Dict{String, Tuple{Float64, Float64}}

function get_data_limits(name::String, dataset::CDFDataset)::Tuple{Float64, Float64}
    haskey(data_limits, name) && return data_limits[name]
    values = Interpolate.convert_to_float64(dataset.ds, name)
    data_limits[name] = (minimum(values), maximum(values))
    data_limits[name]
end

function update_interpolate!(fd::FigureData)::Nothing
    fd.settings.auto_interpolate[] || return nothing
    isnothing(fd.ax[]) && return nothing
    fd.plot_data.plot_type[].type ∉ Constants.GEOGRAPHIC_PLOT_TYPES && return nothing
    # Get the names of x and y coordinates
    x_name = fd.ui.state.x_name[]
    y_name = fd.ui.state.y_name[]
    # Get the dataset
    dataset = fd.plot_data.dataset
    # Get current axis limits
    limits = fd.ax[].computed_limits[]
    xmin, xmax = limits.origin[1], limits.origin[1] + limits.widths[1]
    ymin, ymax = limits.origin[2], limits.origin[2] + limits.widths[2]
    # Get data limits
    xlims = DataLimits.get_data_limits(x_name, dataset)
    ylims = DataLimits.get_data_limits(y_name, dataset)
    # Adjust limits if they exceed data limits
    xmin = max(xmin, xlims[1])
    xmax = min(xmax, xlims[2])
    ymin = max(ymin, ylims[1])
    ymax = min(ymax, ylims[2])
    # Get the size of the axis in pixels
    widths = fd.ax[].scene.viewport[].widths
    # Update the coordinate ranges by setting the kwargs in the UI state
    current_kwargs = fd.ui.state.kwargs[]
    new_kwargs = Dict(
        Symbol(x_name) => (xmin, xmax, widths[1]),
        Symbol(y_name) => (ymin, ymax, widths[2]),
    )
    merged_kwargs = merge(current_kwargs, new_kwargs)
    # Update the UI text box with the new kwargs
    textbox = state.controller.ui.main_menu.plot_menu.plot_kw
    new_kw_string = Plotting.kwarg_dict_to_string(merged_kwargs)
    new_display_string = isempty(new_kw_string) ? " " : new_kw_string
    try
        textbox.displayed_string = new_display_string
        textbox.stored_string = new_kw_string
    catch e
        @warn "Error parsing additional arguments: $e"
    end
    nothing
end


end