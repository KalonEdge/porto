# dmgbuild settings, run through ../make-dmg.sh from app/.
#
# The window is the size of the background, which the app draws itself:
#   .build/out/Products/Debug/Porto --render-dmg-background dmg
# Icon centres match DMGBackground.swift; dmgbuild combines background.png
# with background@2x.png for Retina displays.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides defines)

format = "ULFO"  # LZFSE: smaller and faster to open than zlib; macOS 10.11+
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"

background = "dmg/background.png"
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 12
icon_locations = {
    os.path.basename(app): (170, 164),
    "Applications": (490, 164),
}
