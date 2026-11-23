#!/bin/bash
# Packages the app as the website download: Porto beside an Applications
# shortcut over dmg/background.png. dmgbuild writes the Finder layout itself,
# so this needs no Finder scripting and works in CI. Signs the image when
# CODE_SIGN_IDENTITY is a real identity; release.sh notarizes it.
#
#   ./make-dmg.sh [app] [output.dmg]
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-.build/Porto.app}"
DMG="${2:-.build/Porto.dmg}"
if [[ ! -d "${APP}" ]]; then
    echo "Usage: $0 [app] [output.dmg]  (build the app with ./build-app.sh first)" >&2
    exit 1
fi

VENV=".build/dmgbuild"
if [[ ! -x "${VENV}/bin/dmgbuild" ]]; then
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==1.6.7"
fi

rm -f "${DMG}"
"${VENV}/bin/dmgbuild" -s dmg/settings.py -D app="${APP}" Porto "${DMG}"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "${IDENTITY}" != "-" ]]; then
    codesign --force --sign "${IDENTITY}" --timestamp "${DMG}"
    codesign --verify --strict "${DMG}"
fi
hdiutil verify -quiet "${DMG}"
echo "Built ${DMG} ($(du -h "${DMG}" | cut -f1))"
