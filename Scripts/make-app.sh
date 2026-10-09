#!/usr/bin/env bash
# Builds MonitorBar.app (release binary + icon + Info.plist, ad-hoc signed).
# Usage: Scripts/make-app.sh [output-path]   default: ./MonitorBar.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-MonitorBar.app}"

swift build -c release --product MonitorBar

if [[ ! -f Assets/AppIcon.icns ]]; then
    swift Scripts/generate-icon.swift
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/MonitorBar" "$APP/Contents/MacOS/MonitorBar"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so the bundle launches without an Apple Developer account.
codesign --force --sign - "$APP"

echo "Built $APP"
