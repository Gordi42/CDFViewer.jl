# Installation

## Compiling using PackageCompiler

For optimal performance, I recommend compiling the application using PackageCompiler.jl. This will drastically reduce the startup time of the application. However, it also has some limitations, such as the very big size of the system image (~ 1GB) and the very long compilation time (up to an hour).

For compiling the application, you need to have julia installed on your system. You can download it from [here](https://julialang.org/downloads/).

1. Clone the repository and run the build script:
    ```bash
    git clone https://github.com/Gordi42/CDFViewer.jl.git
    cd CDFViewer.jl
    ./build.sh
    ```
2. After the build is complete, an executable `cdfviewer` will be created in the `build` folder. You can run it using:
    ```bash
    ./build/cdfviewer <path_to_your_file.nc>
    ```

Optionally, you can add the `cdfviewer` executable to your PATH for easier access.

## Running using julia

If you don't want to compile the application, you can run it directly using julia. However, this will result in a longer startup time.

1. Clone the repository:
   ```bash
   git clone https://github.com/Gordi42/CDFViewer.jl.git
   ```
2. Run the application using julia:
   ```bash
   julia --project=/path/to/CDFViewer.jl -e 'using CDFViewer; julia_main()' <path_to_your_file.nc>
   ```

# TODO

## Recording and Saving

- [ ] Add a button for Saving the figure to file (png, svg, jpg, etc.)
- [ ] Add a button for Recording the playback
- [ ] Add a textbox for saving/recording options

## Plot Options

- [ ] Add scatter2d
- [ ] Add scatter2d on 3D axis
- [ ] Add scatter3d
- [ ] Add quiver, streamline (the idea is to add a second variable selection)
- [ ] Add statistical plots (histogram, etc.)
- [ ] Add support for GeoMakie (Various Projections, Coastlines etc.)

## Others

- [ ] Add test workflow for github
- [ ] Add online documentation
- [ ] Set automatic aspect ratios
- [ ] Add support for dark theme
- [ ] Add possibility to add command line arguments
- [ ] Add possibility for default configs in a .config folder
- [ ] Unregular grids ?
- [ ] Dataset distributed over multiple files ?
- [ ] Add a temporary script to open netcdf files
