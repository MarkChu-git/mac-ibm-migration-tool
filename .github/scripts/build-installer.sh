#!/usr/bin/env bash
# Builds Data Shift in the Release configuration and wraps it in an installer
# package that puts "Data Shift.app" in /Applications.
#
# Usage: .github/scripts/build-installer.sh [output-dir]
# Intermediate files go to $RUNNER_TEMP/installer on CI and build/installer locally.
set -euo pipefail

scheme="Data Shift"
app_name="Data Shift.app"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="${RUNNER_TEMP:-$repo_root/build}/installer"
out_dir="${1:-$work_dir/dist}"

rm -rf "$work_dir"
mkdir -p "$work_dir" "$out_dir"

archive="$work_dir/DataShift.xcarchive"
xcodebuild archive \
  -project "$repo_root/migrator.xcodeproj" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$work_dir/DerivedData" \
  -archivePath "$archive" \
  -quiet

app="$archive/Products/Applications/$app_name"
codesign --verify --deep --strict "$app"

info="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info")"
archs="$(lipo -archs "$app/Contents/MacOS/$executable")"
min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
pkg="$out_dir/DataShift-$version-$build.pkg"

# pkgbuild before macOS 27 marks bundles relocatable by default. Turn that off so
# Installer always writes to /Applications instead of updating a copy of the app
# it finds elsewhere on disk. plutil adds the key when pkgbuild leaves it out.
root="$work_dir/root"
mkdir -p "$root"
ditto "$app" "$root/$app_name"
pkgbuild --analyze --root "$root" "$work_dir/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$work_dir/components.plist"
pkgbuild \
  --root "$root" \
  --component-plist "$work_dir/components.plist" \
  --identifier "$bundle_id" \
  --version "$version" \
  --install-location /Applications \
  "$work_dir/DataShift-component.pkg"
productbuild --synthesize --package "$work_dir/DataShift-component.pkg" "$work_dir/distribution.xml"
productbuild --distribution "$work_dir/distribution.xml" --package-path "$work_dir" "$pkg"

sha256="$(shasum -a 256 "$pkg" | cut -d ' ' -f 1)"
echo "Built $pkg ($archs)"
echo "SHA-256: $sha256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "pkg=$pkg"
    echo "name=$(basename "$pkg")"
    echo "version=$version"
    echo "build=$build"
    echo "sha256=$sha256"
    echo "min_os=$min_os"
    echo "archs=$archs"
  } >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### $(basename "$pkg")

- Version $version, build $build ($archs)
- SHA-256: \`$sha256\`
- Ad-hoc signed and not notarized: Gatekeeper blocks the package on first open until it is allowed in System Settings > Privacy & Security.
- Release builds only pair with an identical build, so install this same package on both Macs.
EOF
fi
