#!/bin/sh
# Captures an app's frontmost on-screen window to a PNG, by window id, so
# the agent can look at the real window (SU.12). Needs Screen Recording for
# the app that runs this shell (Xcode, for Xcode's agent).
#   Tools/window-shot.sh SwiftStarGallery /tmp/gallery.png
set -eu
owner=$1
out=$2
id=$(swift - "$owner" <<'SWIFT'
import CoreGraphics
let owner = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
if let w = list.first(where: {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}) { print(w[kCGWindowNumber as String]!) }
SWIFT
)
[ -n "$id" ] || { echo "no on-screen window for $owner" >&2; exit 1; }
screencapture -x -o -l "$id" "$out"
echo "$out"
