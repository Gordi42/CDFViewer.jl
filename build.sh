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



# Create the precompile content script
precompile_content=$(mktemp /tmp/precompile_content.XXXXXX.jl)
cat << EOF > "$precompile_content"
import CDFViewer

include(joinpath(pkgdir(CDFViewer), "test", "runtests.jl"))
EOF

# Create the create_sysimage.jl script
create_sysimage_script=$(mktemp /tmp/create_sysimage.XXXXXX.jl)
cat << EOF > "$create_sysimage_script"
using PackageCompiler
using Pkg
Pkg.activate(".")

create_sysimage(
    ["CDFViewer"],
    sysimage_path = joinpath("$build_dir", "CDFViewer.so"),
    precompile_execution_file = "$precompile_content",
)
EOF

# ==============================================
#  Build the sysimage
# ==============================================
echo "Building the sysimage..."
echo "This may take a very long time..."
julia --project=. "$create_sysimage_script"

# ==============================================
#  Create the executable script
# ==============================================
cat << EOF > "$build_dir/cdfviewer"
#!/bin/bash

julia --project="$project_dir" \
  -J"$build_dir/CDFViewer.so" \
  -e 'using CDFViewer; julia_main()' "$@"
EOF
chmod +x "$build_dir/cdfviewer"

echo "Build complete. The executable is located at: $build_dir/cdfviewer"
echo "Consider adding $build_dir to your PATH."

# ==============================================
#  Clean up
# ==============================================

rm -f "$precompile_content"