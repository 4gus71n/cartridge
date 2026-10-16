#!/bin/bash
# Usage: open_game.sh <Title> [serial]  — scroll the Cartridge feed to <Title> and tap Play.
T="$1"; A="${2:-emulator-5554}"
adb -s $A shell am force-stop com.cartridge.app
adb -s $A shell monkey -p com.cartridge.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6
for i in $(seq 1 24); do
  adb -s $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  if adb -s $A shell cat /sdcard/ui.xml | grep -q "text=\"$T\""; then
    echo "found $T after $i"; adb -s $A shell input tap 720 1560; exit 0
  fi
  # First half scrolls down the feed, second half back up (feed may resume mid-list).
  if [ $i -le 12 ]; then adb -s $A shell input swipe 720 2300 720 700 250
  else adb -s $A shell input swipe 720 900 720 2500 250; fi
  sleep 1.5
done
echo "not found: $T"; exit 1
