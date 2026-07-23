# Installation

CDFViewer requires [Julia](https://julialang.org/downloads/) version `1.12`
or newer and a system with OpenGL support. Any regular desktop or laptop
works, and remote machines can forward the display (see [Remote use](@ref)
below).

## Running with Julia

Clone the repository and instantiate the environment.

```bash
git clone https://github.com/Gordi42/CDFViewer.jl.git
cd CDFViewer.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

The one-time instantiation precompiles the package together with a built-in
workload that covers the whole interactive surface. The app starts in
roughly 10 seconds and runs without compilation pauses on first clicks.

Run the application by passing your file to `julia_main`.

```bash
julia --project=/path/to/CDFViewer.jl -e 'using CDFViewer; julia_main()' your_file.nc
```

!!! tip
    Put a small wrapper script on your `PATH` so the viewer is a single
    command away.

    ```bash
    #!/usr/bin/env bash
    exec julia --project=/path/to/CDFViewer.jl -e 'using CDFViewer; julia_main()' "$@"
    ```

    Save it as `cdfviewer`, make it executable (`chmod +x cdfviewer`), and
    open files with `cdfviewer your_file.nc`. The examples in this manual use
    this form.

## Compiling a system image (optional fast path)

For the fastest startup (about 1 to 3 seconds), you can bake everything into
a system image with
[PackageCompiler](https://julialang.github.io/PackageCompiler.jl/stable/).
The trade-offs are a large system image (several hundred MB) and a long
one-time build.

Run the build script from the repository.

```bash
./build.sh
```

After the build completes, an executable `cdfviewer` is created in the
`build` folder.

```bash
./build/cdfviewer your_file.nc
```

Optionally, add the `cdfviewer` executable to your `PATH` for easier access.

!!! warning
    The system image pins the compiled code, so rebuild it after updating
    the package or its dependencies.

## Prebuilt binary (Linux x86_64)

Each [release](https://github.com/Gordi42/CDFViewer.jl/releases) ships a
self-contained Linux bundle that runs without a Julia installation. It needs
OpenGL drivers and glibc ≥ 2.35 (Ubuntu 22.04 or newer).

```bash
curl -L https://github.com/Gordi42/CDFViewer.jl/releases/latest/download/cdfviewer-linux-x86_64.tar.zst | tar --zstd -x
./cdfviewer/bin/cdfviewer your_file.nc
```

Startup is as fast as the system image path. The bundle is also the easiest
route for CI pipelines, since a workflow can download it and render plots in
about two minutes from job start, without setting up Julia.

```yaml
- name: Install CDFViewer
  run: |
    sudo apt-get update && sudo apt-get install -y xvfb libgl1 zstd
    curl -L https://github.com/Gordi42/CDFViewer.jl/releases/latest/download/cdfviewer-linux-x86_64.tar.zst | tar --zstd -x
- name: Render a plot
  run: |
    xvfb-run -s '-screen 0 1024x768x24' ./cdfviewer/bin/cdfviewer data.nc \
      -v temperature -x lon -y lat -p heatmap \
      --savefig -s 'filename="plot.png"'
```

## Remote use

If you want to run the application on a remote server and forward the
display to your local machine, use SSH with trusted X11 forwarding.

```bash
ssh -Y user@remote
```

On slow network file systems, the [`--use-local`](reference/cli.md) flag
speeds up recording and saving by doing temporary file operations in a local
directory first (see [Configuration](usage/configuration.md)).
