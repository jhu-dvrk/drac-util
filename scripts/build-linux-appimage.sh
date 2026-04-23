#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configure_preset="${CONFIGURE_PRESET:-linux-gcc}"
build_preset="${BUILD_PRESET:-linux-release}"
build_dir="${BUILD_DIR:-$repo_root/build/linux-gcc}"
release_dir="${RELEASE_DIR:-$build_dir/release}"
appdir="$release_dir/dractest.AppDir"
tools_dir="$release_dir/tools"
linuxdeploy_version="${LINUXDEPLOY_VERSION:-1-alpha-20251107-1}"
linuxdeploy_url="${LINUXDEPLOY_URL:-https://github.com/linuxdeploy/linuxdeploy/releases/download/${linuxdeploy_version}/linuxdeploy-x86_64.AppImage}"
linuxdeploy_path="$tools_dir/linuxdeploy-${linuxdeploy_version}-x86_64.AppImage"
project_version="$(sed -n 's/^project([^ ]* VERSION \([^ ]*\) LANGUAGES .*$/\1/p' "$repo_root/CMakeLists.txt")"
final_appimage="$release_dir/dractest-${project_version}-x86_64.AppImage"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --output "$output" "$url"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
    return
  fi

  echo "Need curl or wget to download $url" >&2
  exit 1
}

require_command cmake

mkdir -p "$tools_dir"

cmake --preset "$configure_preset"
cmake --build --preset "$build_preset" --target dractest --parallel

rm -rf "$appdir"
mkdir -p "$appdir"

cmake --install "$build_dir" \
  --component dractest_runtime \
  --prefix "$appdir/usr"

if [[ ! -x "$linuxdeploy_path" ]]; then
  download_file "$linuxdeploy_url" "$linuxdeploy_path"
  chmod +x "$linuxdeploy_path"
fi

rm -f "$release_dir"/*.AppImage

pushd "$release_dir" >/dev/null
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$linuxdeploy_path" \
  --appdir "$appdir" \
  --desktop-file "$appdir/usr/share/applications/dractest.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/dractest.png" \
  --output appimage
popd >/dev/null

generated_appimage="$(find "$release_dir" -maxdepth 1 -type f -name '*.AppImage' ! -name "$(basename "$linuxdeploy_path")" -print -quit)"
if [[ -z "$generated_appimage" ]]; then
  echo "linuxdeploy did not produce an AppImage" >&2
  exit 1
fi

mv -f "$generated_appimage" "$final_appimage"
echo "Created $final_appimage"
