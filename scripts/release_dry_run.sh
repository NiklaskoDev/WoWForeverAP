#!/usr/bin/env bash
# Local dry run of .github/workflows/release.yml: every step except publishing.
# Usage: bash scripts/release_dry_run.sh [tag]   (default tag: v + the VERSION file)
# Never calls git or gh, never creates a tag or a release.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tag="${1:-v$(tr -d '[:space:]' < VERSION)}"

echo "Dry run for tag $tag"
output="$(python tools/release_check.py tag "$tag")"
echo "$output"
version="$(sed -n 's/^version=//p' <<<"$output")"
prerelease="$(sed -n 's/^prerelease=//p' <<<"$output")"

rm -rf dist
python tools/build.py
python tools/release_check.py verify "$version"
python tools/release_check.py notes "$version"

flags="--verify-tag --title $tag"
[ "$prerelease" = "true" ] && flags="$flags --prerelease"
if grep -q '[^[:space:]]' dist/notes.md; then flags="$flags --notes-file notes.md"; else flags="$flags --generate-notes"; fi
echo "Would run: gh release create $tag $flags wow_forever.apworld WoWForeverAP-$version.zip SHA256SUMS"
echo "Dry run finished; nothing was published."
