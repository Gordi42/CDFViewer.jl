#!/bin/bash
set -e

# ==============================================
#  Prepare
# ==============================================
project_dir=$(realpath "$(dirname "$0")")
build_dir="$project_dir/build"
mkdir -p "$build_dir"
rm -f "$build_dir/CDFViewer.so" "$build_dir/cdfviewer"

# ==============================================
#  Build the sysimage
#  (PackageCompiler lives in the build/ environment, not in the app's
#   runtime dependencies.)
# ==============================================
echo "Building the sysimage..."
echo "This may take a while (most compiled code is reused from the package cache)..."

# Parallelize the native-code emission phase of the sysimage build
# (defaults to half the logical cores; needs a few GB RAM per thread).
export JULIA_IMAGE_THREADS="$(nproc)"

julia --project="$build_dir" -e "
using Pkg
Pkg.develop(path = raw\"$project_dir\")
Pkg.instantiate()

using PackageCompiler

create_sysimage(
    [\"CDFViewer\"],
    sysimage_path = joinpath(raw\"$build_dir\", \"CDFViewer.so\"),
    precompile_execution_file = joinpath(raw\"$project_dir\", \"precompile_script.jl\"),
)
"

# Check if the sysimage file was actually created
if [ ! -f "$build_dir/CDFViewer.so" ]; then
  echo "ERROR: Sysimage file was not created at $build_dir/CDFViewer.so"
  exit 1
fi

# ==============================================
#  Strip debug info (~30-50% smaller; stack traces get less detailed)
# ==============================================
if command -v strip >/dev/null 2>&1; then
  echo "Stripping debug info from the sysimage..."
  strip -g "$build_dir/CDFViewer.so"
fi
ls -lh "$build_dir/CDFViewer.so"

# ==============================================
#  Create the executable script
# ==============================================
cat <<EOF >"$build_dir/cdfviewer"
#!/usr/bin/env -S julia --project=$project_dir -J$build_dir/CDFViewer.so --threads=auto

using CDFViewer

julia_main()
EOF
chmod +x "$build_dir/cdfviewer"

echo "Build complete. The executable is located at: $build_dir/cdfviewer"
echo "Consider adding $build_dir to your PATH."
