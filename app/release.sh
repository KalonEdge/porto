#!/bin/bash
# Prepares a release locally: builds and signs the app, notarizes it when
# credentials are set, packages the disk image, and signs the update archive
# and appcast. Publishes nothing. See UPDATES.md.
#
#   ./release.sh <version> <build>     e.g. ./release.sh 1.1 2
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <version> <build>" >&2
    exit 1
fi
if [[ -f release.env ]]; then
    source release.env
fi
export PORTO_VERSION="$1" PORTO_BUILD="$2"
export SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}" SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
REQUIRE_UPDATES=--release python3 scripts/configure.py Info.plist .build/Info.plist

# Notarize with a stored notarytool profile, or an App Store Connect API key (CI).
NOTARY=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    NOTARY=(--keychain-profile "${NOTARYTOOL_PROFILE}")
elif [[ -n "${NOTARY_API_KEY_PATH:-}" ]]; then
    if [[ -z "${NOTARY_API_KEY_ID:-}" || -z "${NOTARY_API_ISSUER_ID:-}" ]]; then
        echo "NOTARY_API_KEY_PATH also needs NOTARY_API_KEY_ID and NOTARY_API_ISSUER_ID." >&2
        exit 1
    fi
    NOTARY=(--key "${NOTARY_API_KEY_PATH}" --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER_ID}")
fi
if [[ ${#NOTARY[@]} -gt 0 && "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    echo "Notarization needs CODE_SIGN_IDENTITY set to a Developer ID Application certificate." >&2
    exit 1
fi
if [[ ${#NOTARY[@]} -eq 0 ]]; then
    echo "warning: not notarizing. Gatekeeper will warn on first launch of a downloaded copy." >&2
fi

# Sparkle signs with the login Keychain key unless given an exported key file (CI).
SPARKLE_KEY=()
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    SPARKLE_KEY=(--ed-key-file "${SPARKLE_PRIVATE_KEY_FILE}")
fi

UPDATES=".build/updates"
ARCHIVE="Porto-${PORTO_BUILD}.zip"
if [[ -e "${UPDATES}/${ARCHIVE}" ]]; then
    echo "${UPDATES}/${ARCHIVE} exists. Every release needs a new, higher build number." >&2
    exit 1
fi

./build-app.sh --release
APP=".build/Porto.app"
DMG=".build/Porto.dmg"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

notarize() {
    local result id status
    result="$(xcrun notarytool submit "$1" "${NOTARY[@]}" --wait --output-format json)"
    read -r id status < <(python3 -c 'import json, sys; r = json.load(sys.stdin); print(r["id"], r["status"])' <<< "${result}")
    if [[ "${status}" != "Accepted" ]]; then
        xcrun notarytool log "${id}" "${NOTARY[@]}" >&2 || true
        echo "Notarizing $1 ended with status ${status}." >&2
        exit 1
    fi
    xcrun stapler staple "$1"
    xcrun stapler validate "$1"
}

if [[ ${#NOTARY[@]} -gt 0 ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${APP}" .build/notarize.zip
    notarize .build/notarize.zip
    xcrun stapler staple "${APP}"
    spctl --assess --type execute --verbose=2 "${APP}"
fi

./make-dmg.sh "${APP}" "${DMG}"
if [[ ${#NOTARY[@]} -gt 0 ]]; then
    notarize "${DMG}"
    spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
fi

# Sign into a staging copy and only replace .build/updates once everything worked.
STAGING="$(mktemp -d .build/updates-staging.XXXXXX)"
trap 'rm -rf "${STAGING}"' EXIT
mkdir -p "${STAGING}/updates"
if [[ -d "${UPDATES}" ]]; then
    ditto "${UPDATES}" "${STAGING}/updates"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${STAGING}/updates/${ARCHIVE}"
SIGNATURE="$("${TOOLS}/sign_update" ${SPARKLE_KEY[@]+"${SPARKLE_KEY[@]}"} -p "${STAGING}/updates/${ARCHIVE}")"
swift scripts/verify-update-signature.swift "${SPARKLE_PUBLIC_KEY}" "${STAGING}/updates/${ARCHIVE}" "${SIGNATURE}"
"${TOOLS}/generate_appcast" ${SPARKLE_KEY[@]+"${SPARKLE_KEY[@]}"} --download-url-prefix "${SPARKLE_FEED_URL%/*}/" "${STAGING}/updates"
ditto "${STAGING}/updates" "${UPDATES}"

echo "Prepared ${UPDATES}/${ARCHIVE}, ${UPDATES}/appcast.xml and ${DMG}."
echo "Publish ${UPDATES}/ at ${SPARKLE_FEED_URL%/*}/ and use ${DMG} as the website download."
