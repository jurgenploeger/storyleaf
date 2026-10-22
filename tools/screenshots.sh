#!/bin/bash
# Launches the built app in a booted simulator once per scene and saves a screenshot of each
# (and a video of the scenes with record=N).
# macOS only (needs Xcode). Used by .github/workflows/screenshots.yml; also works locally:
#
#   tools/screenshots.sh <simulator-udid> <path/to/Storyleaf.app> <out-dir> [scenes-file] [only-these,names]
set -euo pipefail

SIM="$1"; APP="$2"; OUT="$3"; SCENES="${4:-tools/screenshots.txt}"; ONLY="${5:-}"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
mkdir -p "$OUT"

xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 || true

grep -vE '^\s*(#|$)' "$SCENES" | while IFS='|' read -r name flags wait; do
  name=$(echo "$name" | xargs); flags=$(echo "$flags" | xargs); wait=$(echo "$wait" | xargs)
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi
  echo "▶ $name ($flags)"
  # Crash reports written after this are this scene's (see the end of the loop).
  touch "$OUT/.scene-start"
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  # Fresh data for every scene, so the title screen never shows a leftover save.
  xcrun simctl uninstall "$SIM" "$BUNDLE" && xcrun simctl install "$SIM" "$APP"
  # Right after a reinstall the simulator sometimes doesn't know the app yet ("unknown to
  # FrontBoard"), so give the launch a few tries.
  for attempt in 1 2 3 4; do
    if SIMCTL_CHILD_STORYLEAF_DEBUG="$flags" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null; then break; fi
    if [ "$attempt" = 4 ]; then echo "✗ couldn't launch for $name" >&2; exit 1; fi
    echo "  launch failed, retrying ($attempt)…"
    sleep 3
  done
  # Startup can take a long while on a CI simulator, and how long varies from run to run. The
  # white launch screen makes a tiny PNG (~70 KB) and anything the game draws a far bigger one,
  # so wait for the first real frame, then give the scene its own seconds to settle.
  # Debug games (newgame) mark Documents/debug-ready once the map or battle is up; the title
  # screen doesn't, so it goes by size. How to play's parts (clip=n) mark it as their part
  # starts, and their seconds count from that moment, so they look for it more often.
  start=$SECONDS
  ready=""
  poll=3
  if [[ ",$flags," == *",newgame,"* || ",$flags," == *",clip="* ]]; then
    ready="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data 2>/dev/null)/Documents/debug-ready"
  fi
  if [[ ",$flags," == *",clip="* ]]; then poll=0.5; fi
  # The continent lays out the lands round you before its first frame (several on CI's simulator).
  limit=480
  sleep "$poll"
  while :; do
    if [ -n "$ready" ]; then
      [ -f "$ready" ] && break
    else
      xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 || true
      size=$(stat -f%z "$OUT/$name.png" 2>/dev/null || echo 0)
      [ "$size" -gt 300000 ] && break
    fi
    if [ $((SECONDS - start)) -gt "$limit" ]; then echo "  still on the launch screen after $limit s"; break; fi
    sleep "$poll"
  done
  echo "::notice::$name: first frame after $((SECONDS - start)) s"
  # record=N: film the screen for N seconds from the first frame (the app preview video), then
  # take the screenshot as usual.
  record=$(echo ",$flags," | grep -oE ',record=[0-9]+,' | grep -oE '[0-9]+' || true)
  if [ -n "$record" ]; then
    xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
    recorder=$!
    sleep "$record"
    kill -INT "$recorder" 2>/dev/null || true
    wait "$recorder" 2>/dev/null || true
    ls -l "$OUT/$name.mp4" || echo "::warning::$name: no recording"
  fi
  sleep "${wait:-8}"
  # The whole screen, corners and all. The simulator draws the Dynamic Island into it, though;
  # tools/store_slides.py crops it off the App Store slides.
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png"
  # The simulator stays in portrait, so a landscape-locked app comes out sideways; turn it upright.
  if [[ ",$flags," == *",landscape,"* ]]; then sips -r 270 "$OUT/$name.png" >/dev/null; fi
  # A crash shows as the home screen; say so, with why and where (the crashed thread's frames).
  find ~/Library/Logs/DiagnosticReports -name 'Storyleaf*.ips' -newer "$OUT/.scene-start" 2>/dev/null | while read -r report; do
    echo "::error::$name: the app crashed ($(basename "$report"))"
    python3 - "$report" <<'PY' || head -c 6000 "$report"
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text.split("\n", 1)[1])
print("  exception:", body.get("exception"), "| termination:", (body.get("termination") or {}).get("indicator"))
for source, lines in (body.get("asi") or {}).items():
    print("  ", source, lines)
images = body.get("usedImages") or []
thread = (body.get("threads") or [{}])[body.get("faultingThread", 0)]
def show(frame):
    index = frame.get("imageIndex")
    image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
    where = f"{frame.get('sourceFile', '')}:{frame.get('sourceLine', '')}" if frame.get("sourceFile") else ""
    print(f"    {image:<28} {frame.get('symbol', hex(frame.get('imageOffset', 0)))} {where}")
for frame in (thread.get("frames") or [])[:30]:
    show(frame)
# Any other thread that was in the app's own code then (a race shows up here), its frames there.
for number, other in enumerate(body.get("threads") or []):
    if number == body.get("faultingThread", 0):
        continue
    ours = [f for f in other.get("frames") or []
            if f.get("imageIndex") is not None and f["imageIndex"] < len(images)
            and "Storyleaf" in images[f["imageIndex"]].get("name", "")]
    if ours:
        print(f"  thread {number} ({other.get('queue') or other.get('name') or '?'}):")
        for frame in ours[:12]:
            show(frame)
PY
  done || true
done
