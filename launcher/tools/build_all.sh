#!/bin/bash
# Builds the Windows launcher and the Android companion app, and puts the app
# (with companion/version.json) beside the launcher so it can update phones.
#
#   tools/build_all.sh <out dir> <keystore dir>
#
# <keystore dir> holds companion-release.jks and companion-release.txt
# (alias=..., password=...). Keep them: Android only installs an update over
# the app when it's signed with the same key.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-../shl-build}
KEYS=${2:-../shl-keys}
G=${GODOT:-/opt/godot/Godot_v4.7-stable_linux.x86_64}

VER=$(grep -oP 'const APP_VERSION := "\K[^"]+' core/companion/client.gd)
CODE=$(grep -oP 'const APP_CODE := \K[0-9]+' core/companion/client.gd)
sed -i "s/^version\/code=.*/version\/code=$CODE/; s/^version\/name=.*/version\/name=\"$VER\"/" export_presets.cfg

mkdir -p "$OUT/companion"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(cd "$KEYS" && pwd)/companion-release.jks"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=$(grep -oP '^alias=\K.*' "$KEYS/companion-release.txt")
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$(grep -oP '^password=\K.*' "$KEYS/companion-release.txt")

$G --headless --path . --import >/dev/null 2>&1 || true
$G --headless --path . --export-release "Windows" "$OUT/Silent Hills.exe" 2>&1 | grep -E "ERROR" || true
$G --headless --path . --export-release "Android" "$OUT/companion/SilentHillsCompanion.apk" 2>&1 | grep -E "ERROR" || true
rm -f "$OUT/companion/SilentHillsCompanion.apk.idsig"
SHA=$(sha256sum "$OUT/companion/SilentHillsCompanion.apk" | cut -d' ' -f1)
printf '{"version": "%s", "code": %s, "sha256": "%s"}\n' "$VER" "$CODE" "$SHA" > "$OUT/companion/version.json"
cat "$OUT/companion/version.json"
ls -la "$OUT" "$OUT/companion"
