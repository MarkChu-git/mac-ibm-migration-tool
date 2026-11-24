#!/usr/bin/env bash
# Publishes the GitHub release for the pushed tag with the installer package attached.
#
# Usage: .github/scripts/publish-release.sh <pkg-path>
# Reads TAG, VERSION, BUILD, SHA256, MIN_OS, ARCHS and RUN_URL from the environment,
# plus GITHUB_REPOSITORY, GITHUB_SHA and GH_TOKEN, which Actions provides.
set -euo pipefail

pkg="$1"
name="$(basename "$pkg")"
title="Version $VERSION Build $BUILD"
flags=()

# IBM tags releases v-<version>-b-<build> and adds a suffix such as -rc1 or -b1 to
# pre-releases. The same rule applies here: only a tag without a suffix is final.
if [[ "$TAG" =~ ^v-([0-9.]+)-b-([0-9]+)(-(.+))?$ ]]; then
  if [[ "${BASH_REMATCH[1]}" != "$VERSION" || "${BASH_REMATCH[2]}" != "$BUILD" ]]; then
    echo "::error::Tag $TAG does not match the app version $VERSION ($BUILD)."
    exit 1
  fi
  suffix="${BASH_REMATCH[4]}"
  if [[ -n "$suffix" ]]; then
    title+=" ($suffix)"
    flags+=(--prerelease)
  fi
else
  flags+=(--prerelease)
fi

notes="$(mktemp)"
cat > "$notes" <<EOF
Installer for Data Shift $VERSION, build $BUILD, built by GitHub Actions from \`$TAG\` at ${GITHUB_SHA:0:7}.

### Install

Open \`$name\`, or run:

\`\`\`
sudo installer -pkg $name -target /
\`\`\`

Data Shift installs to /Applications and needs macOS $MIN_OS or later. Architectures: $ARCHS.

### Before you install

- The package is unsigned, and the app is ad-hoc signed without notarization. macOS blocks the downloaded package the first time you open it; allow it in System Settings > Privacy & Security.
- Release builds pair only with the identical build. Put this same package on both the old and the new Mac, because it won't pair with any other build of Data Shift, IBM's included.

SHA-256 of the package: \`$SHA256\`

Build run: $RUN_URL
EOF

gh release create "$TAG" "$pkg" \
  --repo "$GITHUB_REPOSITORY" \
  --verify-tag \
  --title "$title" \
  --notes-file "$notes" \
  --generate-notes \
  ${flags[@]+"${flags[@]}"}
