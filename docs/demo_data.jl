# Builds the small synthetic NetCDF files used throughout the documentation.
# All fields are smooth analytic functions (no random numbers), so every doc
# build renders identical data.

using NCDatasets: NCDataset, defVar

"""
Create the structured demo dataset (`demo.nc`) with three variables on a
lon/lat/lev/time grid.
"""
function create_demo_file(dir::String)::String
    file = joinpath(dir, "demo.nc")
    nlon, nlat, nlev, ntime = 72, 36, 10, 24
    lon = collect(range(-180.0, 175.0, nlon))
    lat = collect(range(-87.5, 87.5, nlat))
    lev = collect(range(0.0, 18.0, nlev))
    time = collect(0.0:ntime-1)

    # Zonal-mean temperature with a lapse rate and a slowly traveling wave
    temperature = [
        -8.0 + 36.0 * cosd(la)^2 - 1.3 * le +
        4.0 * cosd(2 * (lo + 15.0 * t)) * cosd(la)^2 * exp(-le / 12.0)
        for lo in lon, la in lat, le in lev, t in time
    ]

    # A drifting large-scale moisture pattern
    humidity = [
        55.0 + 25.0 * sind(2 * la + 10.0 * t) * cosd(lo + 15.0 * t) +
        15.0 * cosd(la)^2
        for lo in lon, la in lat, t in time
    ]

    # Static field: subtropical highs and polar lows
    pressure = [
        1013.0 + 12.0 * cosd(2 * la)^3 * sind(la)^2 - 8.0 * cosd(la / 2)^8 +
        3.0 * sind(2 * lo) * cosd(la)
        for lo in lon, la in lat
    ]

    NCDataset(file, "c", attrib = Dict{String, Any}(
        "title" => "CDFViewer documentation demo dataset")) do ds
        defVar(ds, "lon", lon, ("lon",), attrib = Dict(
            "standard_name" => "longitude", "units" => "degrees_east"))
        defVar(ds, "lat", lat, ("lat",), attrib = Dict(
            "standard_name" => "latitude", "units" => "degrees_north"))
        defVar(ds, "lev", lev, ("lev",), attrib = Dict(
            "long_name" => "height", "units" => "km"))
        defVar(ds, "time", time, ("time",), attrib = Dict(
            "units" => "days since 2000-01-01 00:00:00"))

        defVar(ds, "temperature", temperature, ("lon", "lat", "lev", "time"),
            attrib = Dict("units" => "degC", "long_name" => "Air temperature"))
        defVar(ds, "humidity", humidity, ("lon", "lat", "time"),
            attrib = Dict("units" => "%", "long_name" => "Relative humidity"))
        defVar(ds, "pressure", pressure, ("lon", "lat"),
            attrib = Dict("units" => "hPa", "long_name" => "Surface pressure"))
    end
    file
end

"""
Create an idealized (non-geographic) demo dataset (`wave.nc`): a circular
surface wave expanding from the center of a 2 km × 2 km domain, plus a static
3D pressure pulse for the volume-rendering examples.
"""
function create_wave_file(dir::String)::String
    file = joinpath(dir, "wave.nc")
    nx, ny, nz, ntime = 161, 161, 33, 73
    x = collect(range(0.0, 2000.0, nx))
    y = collect(range(0.0, 2000.0, ny))
    z = collect(range(0.0, 500.0, nz))
    time = collect(range(0.0, 36.0, ntime))

    # Ring-shaped wave packet traveling outward at 45 m/s, decaying with radius
    function ring(xi, yj, t)
        r = hypot(xi - 1000.0, yj - 1000.0)
        s = r - 45.0 * t
        6.0 * cos(0.025 * s) * exp(-(s / 400.0)^2) * 500.0 / (r + 500.0)
    end
    eta = [ring(xi, yj, t) for xi in x, yj in y, t in time]

    # Concentric pressure rings concentrated at mid-depth
    function rings3d(xi, yj, zk)
        r = hypot(xi - 1000.0, yj - 1000.0)
        cos(0.02 * r) * exp(-r / 700.0) * exp(-((zk - 250.0) / 130.0)^2)
    end
    pwave = [rings3d(xi, yj, zk) for xi in x, yj in y, zk in z]

    NCDataset(file, "c", attrib = Dict{String, Any}(
        "title" => "Idealized wave demo")) do ds
        defVar(ds, "x", x, ("x",), attrib = Dict("units" => "m"))
        defVar(ds, "y", y, ("y",), attrib = Dict("units" => "m"))
        defVar(ds, "z", z, ("z",), attrib = Dict("units" => "m"))
        defVar(ds, "time", time, ("time",), attrib = Dict("units" => "s"))

        defVar(ds, "eta", eta, ("x", "y", "time"), attrib = Dict(
            "units" => "cm", "long_name" => "Surface elevation"))
        defVar(ds, "pwave", pwave, ("x", "y", "z"), attrib = Dict(
            "units" => "hPa", "long_name" => "Pressure perturbation"))
    end
    file
end

"""
Create an ICON-style pair (`atmos.nc` + `icon_grid_0013_R02B04_G.nc`): the
data file stores a variable on an `ncells` dimension but no coordinates; the
grid file provides `clon`/`clat` in radians. Cell positions come from a
Fibonacci lattice, so they are irregular but deterministic.
"""
function create_icon_demo(dir::String)::Tuple{String, String}
    ncells, ntime = 4000, 12
    golden = π * (3.0 - sqrt(5.0))
    # Fibonacci lattice on the sphere (radians)
    clat = [asin(1.0 - 2.0 * (i - 0.5) / ncells) for i in 1:ncells]
    clon = [mod(i * golden + π, 2π) - π for i in 1:ncells]

    temp2m = [
        16.0 + 12.0 * cos(clat[c])^2 +
        3.0 * cos(3 * clon[c] + 0.5 * t) * cos(clat[c])^2 +
        2.0 * sin(2 * clat[c] + 0.4 * t)
        for c in 1:ncells, t in 0.0:ntime-1
    ]

    data_file = joinpath(dir, "atmos.nc")
    NCDataset(data_file, "c", attrib = Dict{String, Any}(
        "title" => "Unstructured demo output",
        "uuidOfHGrid" => "docs-demo-grid-0013")) do ds
        defVar(ds, "time", collect(0.0:ntime-1), ("time",), attrib = Dict(
            "units" => "days since 2000-01-01 00:00:00"))
        defVar(ds, "temp2m", temp2m, ("ncells", "time"), attrib = Dict(
            "units" => "degC", "long_name" => "2 m air temperature",
            "coordinates" => "clat clon"))
    end

    grid_file = joinpath(dir, "icon_grid_0013_R02B04_G.nc")
    NCDataset(grid_file, "c", attrib = Dict{String, Any}(
        "uuidOfHGrid" => "docs-demo-grid-0013")) do ds
        defVar(ds, "clon", clon, ("cell",), attrib = Dict(
            "standard_name" => "longitude", "units" => "radian"))
        defVar(ds, "clat", clat, ("cell",), attrib = Dict(
            "standard_name" => "latitude", "units" => "radian"))
    end

    data_file, grid_file
end
