#!/bin/bash

# ==============================================
#  Prepare
# ==============================================

# Empty the build directory if it exists
if [ -d "build" ]; then
    rm -rf build/*
else
    mkdir build
fi
project_dir=$(realpath .)
build_dir=$(realpath build)


# Create the create_sysimage.jl script
create_sysimage_script=$(mktemp /tmp/create_sysimage.XXXXXX.jl)
cat << EOF > "$create_sysimage_script"
using PackageCompiler
using Pkg
Pkg.activate(".")

create_sysimage(
    ["CDFViewer"],
    sysimage_path = joinpath("$build_dir", "CDFViewer.so"),
    precompile_execution_file = "$project_dir/precompile_script.jl",
)
EOF

# ==============================================
#  Build the sysimage
# ==============================================
echo "Building the sysimage..."
echo "This may take a very long time..."
julia --project=. "$create_sysimage_script"

# Check if the build succeeded
if [ $? -ne 0 ]; then
    echo "ERROR: Sysimage build failed!"
    rm -f "$create_sysimage_script"
    exit 1
fi

# Check if the sysimage file was actually created
if [ ! -f "$build_dir/CDFViewer.so" ]; then
    echo "ERROR: Sysimage file was not created at $build_dir/CDFViewer.so"
    rm -f "$create_sysimage_script"
    exit 1
fi

# ==============================================
#  Create the executable script
# ==============================================
cat << EOF > "$build_dir/cdfviewer"
#!/bin/bash

julia --threads auto--project="$project_dir" \
  -J"$build_dir/CDFViewer.so" \
  -e 'using CDFViewer; julia_main()' "$@"
EOF
chmod +x "$build_dir/cdfviewer"

echo "Build complete. The executable is located at: $build_dir/cdfviewer"
echo "Consider adding $build_dir to your PATH."

# ==============================================
#  Clean up
# ==============================================

rm -f "$create_sysimage_script"