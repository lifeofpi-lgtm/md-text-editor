#!/bin/bash
# usage: shot.sh out.png  -> captures the first on-screen MDmaster window by id
OUT="$1"
# Stage Manager parks inactive windows as tiny thumbnails; bring the app forward first.
osascript -e 'tell application "MDmaster" to activate' >/dev/null 2>&1; sleep 1.2
ID=$(swift -e '
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w["kCGWindowOwnerName"] as? String) == "MDmaster" && (w["kCGWindowLayer"] as? Int) == 0 {
  print(w["kCGWindowNumber"] as! Int); break
}' 2>/dev/null)
echo "window id: $ID"
[ -n "$ID" ] && screencapture -x -o -l "$ID" "$OUT" && echo saved "$OUT"
