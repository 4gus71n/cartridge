#!/bin/bash
# Usage: [FEED_SHOT=feed.png] open_game.sh <Title> [serial]
# Relaunch the Cartridge app, scroll the feed to <Title>, optionally screenshot
# the reel, then tap Play. Scans down then back up (the feed may resume mid-list);
# the scan length follows the catalog size reported by the local backend.
T="$1"; A="${2:-emulator-5554}"
N=$(curl -s "localhost:8123/games?status=verified" 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
N=${N:-20}; N=$((N + 2))
adb -s $A shell am force-stop com.cartridge.app
adb -s $A shell monkey -p com.cartridge.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6
for i in $(seq 1 $((N * 2))); do
  adb -s $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  if adb -s $A shell cat /sdcard/ui.xml | grep -q "text=\"$T\""; then
    echo "found $T after $i"
    [ -n "$FEED_SHOT" ] && adb -s $A exec-out screencap -p > "$FEED_SHOT"
    adb -s $A shell input tap 720 1560; exit 0
  fi
  if [ $i -le $N ]; then adb -s $A shell input swipe 720 2300 720 700 250
  else adb -s $A shell input swipe 720 900 720 2500 250; fi
  sleep 1.5
done
echo "not found: $T"; exit 1
