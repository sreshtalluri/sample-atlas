#!/bin/bash
# Assemble a double-clickable "Sample Atlas.app" in dist/ with the sound-search
# worker and a pinned uv binary inside, ad-hoc signed. Usage: scripts/make-app.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
app="$dist/Sample Atlas.app"
resources="$app/Contents/Resources/semantic"

uv_version="0.12.11"
uv_sha_aarch64="e01b69ee15e81918d5e8fc9cf39b3db7f59c5576e5e306cd9b7aeb2c7b7321c3"
uv_sha_x86_64="96d773bf5fda4f9b08c4444847f9183d1c14bc8a28ff9c0490e261a8fc6e5309"

version="$(git -C "$root" describe --tags --always 2>/dev/null || echo dev)"
build_number="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64 --package-path "$root"
binary="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$root" --show-bin-path)/SampleAtlas"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$resources"
cp "$binary" "$app/Contents/MacOS/SampleAtlas"
cp "$root/semantic/worker.py" "$root/semantic/pyproject.toml" "$root/semantic/uv.lock" "$root/semantic/model-revision.txt" "$resources/"

for arch in aarch64 x86_64; do
  tarball="$dist/uv-$arch-apple-darwin-$uv_version.tar.gz"
  if [ ! -f "$tarball" ]; then
    echo "Downloading uv $uv_version for ${arch}..."
    curl -fsSL -o "$tarball" "https://github.com/astral-sh/uv/releases/download/$uv_version/uv-$arch-apple-darwin.tar.gz"
  fi
  expected_var="uv_sha_$arch"
  echo "${!expected_var}  $tarball" | shasum -a 256 -c - >/dev/null
  tar -xzf "$tarball" -C "$dist" "uv-$arch-apple-darwin/uv"
  mv "$dist/uv-$arch-apple-darwin/uv" "$resources/uv-$arch"
  rmdir "$dist/uv-$arch-apple-darwin"
done

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Sample Atlas</string>
  <key>CFBundleExecutable</key><string>SampleAtlas</string>
  <key>CFBundleIdentifier</key><string>com.sreshtalluri.SampleAtlas</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Sample Atlas</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version#v}</string>
  <key>CFBundleVersion</key><string>$build_number</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" "$dist/Sample-Atlas-macos.zip"
echo "Built $app ($version) and $dist/Sample-Atlas-macos.zip"
