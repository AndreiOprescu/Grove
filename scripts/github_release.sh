#!/bin/bash
# Put the release files of Grove on GitHub, so each copy of Grove sees the
# new version and shows its update card. Run scripts/flutter_release.sh for
# each platform first. The steps are in docs/acceptance/F12-release.md.
#
#   scripts/github_release.sh          the version of app/pubspec.yaml
#
# The tag is v<version>, for example v1.0.1. The files Grove looks for:
#
#   grove-macos.zip     from scripts/flutter_release.sh macos
#   grove-windows.zip   made here from grove-windows/ (flutter_release windows)
#   grove-android.apk   from scripts/flutter_release.sh android
#
# A new release gets the files that are there now. When the release is
# there already (made on another computer), only the files it does not have
# yet go up: a Mac and a Windows PC can each add their own.
#
# This publishes: everyone can see the release. It needs `gh auth login`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/app"

version="$(sed -n 's/^version: *\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)"
if [ -z "$version" ]; then
  echo "No version x.y.z in app/pubspec.yaml." >&2
  exit 1
fi
core="$(sed -n "s/.*version = '\([^']*\)'.*/\1/p" lib/core/grove_core.dart)"
if [ "$core" != "$version" ]; then
  echo "app/pubspec.yaml says $version but GroveCore.version says $core." >&2
  echo "Make them the same, then run this again." >&2
  exit 1
fi
tag="v$version"

dist=build/dist
if [ -d "$dist/grove-windows" ]; then
  rm -f "$dist/grove-windows.zip"
  (cd "$dist" && zip -qr grove-windows.zip grove-windows)
fi

files=()
for name in grove-macos.zip grove-windows.zip grove-android.apk; do
  if [ -f "$dist/$name" ]; then files+=("$dist/$name"); fi
done
if [ ${#files[@]} -eq 0 ]; then
  echo "No release files in app/$dist. Run scripts/flutter_release.sh first." >&2
  exit 1
fi

if gh release view "$tag" >/dev/null 2>&1; then
  have="$(gh release view "$tag" --json assets --jq '.assets[].name')"
  missing=()
  for file in "${files[@]}"; do
    if ! grep -qx "$(basename "$file")" <<<"$have"; then missing+=("$file"); fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    echo "Release $tag has all the files of this computer. Nothing to do."
    exit 0
  fi
  gh release upload "$tag" "${missing[@]}"
  echo "Added to release $tag: ${missing[*]}"
else
  gh release create "$tag" "${files[@]}" \
    --title "Grove $version" --generate-notes --latest
  echo "Made release $tag with: ${files[*]}"
fi
