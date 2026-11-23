#!/bin/bash
# Builds Porto, signs it locally (ad-hoc, or with CODE_SIGN_IDENTITY when set)
# and installs it in /Applications so it opens from Launchpad and Spotlight.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh
pkill -f "/Applications/Porto.app/Contents/MacOS/Porto" || true
rm -rf /Applications/Porto.app
ditto .build/Porto.app /Applications/Porto.app
xattr -dr com.apple.quarantine /Applications/Porto.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Porto.app
codesign --verify --deep --strict /Applications/Porto.app
open /Applications/Porto.app
echo "Installed /Applications/Porto.app"
