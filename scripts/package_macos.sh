#!/bin/bash
set -euo pipefail
app="${1:?App bundle required}"
version="${2:?Version required}"
output="${3:?Output directory required}"
[[ -d "$app/Contents" ]] || { echo 'App bundle missing'; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid package version'; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root" "$output"
ditto "$app" "$stage/root/Nekoloc.app"
pkgbuild --analyze --root "$stage/root" "$stage/components.plist"
python3 - "$stage/components.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    components = plistlib.load(f)
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleOverwriteAction'] = 'upgrade'
with open(path, 'wb') as f:
    plistlib.dump(components, f)
PY
pkgbuild --root "$stage/root" --component-plist "$stage/components.plist" \
  --install-location /Applications --identifier net.zerexa.nekoloc \
  --version "$version" --ownership recommended "$output/Nekoloc-macOS-Installer.pkg"
pkgutil --payload-files "$output/Nekoloc-macOS-Installer.pkg" > "$stage/payload.txt"
grep -q 'Nekoloc.app/Contents/Info.plist' "$stage/payload.txt"
