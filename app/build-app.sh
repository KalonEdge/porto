#!/bin/bash
# Builds .build/Porto.app from a release build: the binary, its fonts, icon,
# translations and Sparkle, signed from the inside out. Ad-hoc signed unless
# CODE_SIGN_IDENTITY names a Developer ID certificate.
#
#   ./build-app.sh            local build, no update feed needed
#   ./build-app.sh --release  also requires the update feed (see UPDATES.md)
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
    "" | --release) ;;
    *) echo "Usage: $0 [--release]" >&2; exit 1 ;;
esac
if [[ -f release.env ]]; then
    source release.env
fi
export REQUIRE_UPDATES="${1:-}"
export SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}" SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
export PORTO_VERSION="${PORTO_VERSION:-}" PORTO_BUILD="${PORTO_BUILD:-}"
export PORTO_REPOSITORY="${PORTO_REPOSITORY:-}" PORTO_WEBSITE="${PORTO_WEBSITE:-}"

APP=".build/Porto.app"
CONTENTS="${APP}/Contents"

# Validate the configuration before spending time on a build.
python3 scripts/configure.py Info.plist .build/Info.plist
swift build -c release --product Porto
BIN="$(swift build -c release --show-bin-path)"
for required in "${BIN}/Porto" "${BIN}/Porto_Porto.bundle" "${BIN}/Sparkle.framework" Resources/AppIcon.icns; do
    if [[ ! -e "${required}" ]]; then
        echo "Missing ${required}" >&2
        exit 1
    fi
done

rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources" "${CONTENTS}/Frameworks"
ditto "${BIN}/Porto" "${CONTENTS}/MacOS/Porto"
cp .build/Info.plist "${CONTENTS}/Info.plist"
ditto Resources/Fonts "${CONTENTS}/Resources/Fonts"
cp Resources/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"
ditto "${BIN}/Porto_Porto.bundle" "${CONTENTS}/Resources/Porto_Porto.bundle"
ditto "${BIN}/Sparkle.framework" "${CONTENTS}/Frameworks/Sparkle.framework"

# Inside out: Sparkle's helpers (keeping their entitlements), the framework,
# the translations bundle, then the app.
IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "${IDENTITY}" == "-" ]]; then
    SIGN=(--force --sign - --timestamp=none)
else
    SIGN=(--force --sign "${IDENTITY}" --options runtime --timestamp)
fi
SPARKLE="${CONTENTS}/Frameworks/Sparkle.framework/Versions/B"
for part in "${SPARKLE}/XPCServices/Downloader.xpc" "${SPARKLE}/XPCServices/Installer.xpc" \
            "${SPARKLE}/Autoupdate" "${SPARKLE}/Updater.app" "${CONTENTS}/Frameworks/Sparkle.framework"; do
    codesign "${SIGN[@]}" --preserve-metadata=entitlements "${part}"
done
codesign "${SIGN[@]}" "${CONTENTS}/Resources/Porto_Porto.bundle"
codesign "${SIGN[@]}" "${APP}"
codesign --verify --deep --strict "${APP}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS}/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${CONTENTS}/Info.plist")"
echo "Built ${APP} (Porto ${VERSION}, build ${BUILD}, $(du -sh "${APP}" | cut -f1))"
echo "Run it with: open ${APP}"
