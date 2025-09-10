using ArgParse
using Revise
using Test
using GLMakie
using CDFViewer
using CDFViewer.Constants
using CDFViewer.Data
using CDFViewer.UI
using CDFViewer.Plotting
using CDFViewer.Controller

NS = Constants.NOT_SELECTED_LABEL

include("test_setup.jl")

controller = Controller.ViewerController(make_temp_dataset(), headless=false)


# controller.fd.fig

# fname = "/home/silvano/OneDrive/Programmieren/netCDF_Project/Rust/nci_test/data/era_data.nc"

# dataset = Data.CDFDataset(fname)

# controller = Controller.ViewerController(dataset, visible=true)
