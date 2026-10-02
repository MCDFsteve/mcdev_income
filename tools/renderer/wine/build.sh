#!/bin/sh
# Build from a fresh Wine 11.0 source tree. Requires Xcode CLI tools and Bison 3.8+.
# MCDev contributors 2026; LGPL-2.1-or-later.
set -eu
source_tree=${1:?Usage: build.sh /absolute/wine-wine-11.0 /absolute/build-directory}
build_tree=${2:?Build directory required}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test -f "$source_tree/configure"
patch -d "$source_tree" -p1 < "$script_dir/wine-11.0-dxmt.patch"
mkdir -p "$build_tree"
cd "$build_tree"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CC='clang -arch x86_64'
export CXX='clang++ -arch x86_64'
export CFLAGS='-O2'
darwin_version=$(uname -r)
"$source_tree/configure" \
  --build="x86_64-apple-darwin$darwin_version" \
  --host="x86_64-apple-darwin$darwin_version" \
  --enable-archs=x86_64 \
  --without-x --without-alsa --without-pulse --without-dbus --without-gstreamer
make -j8 dlls/winemac.drv/winemac.so
codesign --force --sign - dlls/winemac.drv/winemac.so
nm -gU dlls/winemac.drv/winemac.so | rg '_macdrv_functions$'
shasum -a 256 dlls/winemac.drv/winemac.so
# The application asset is not replaced automatically. Review the result and
# update wineMetalBridgeHash if intentionally shipping a newly built driver.
