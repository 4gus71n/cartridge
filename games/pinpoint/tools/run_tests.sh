#!/bin/bash
# Gate: import + every tests/*_check.gd. RED on non-zero exit, SCRIPT ERROR,
# or a suite that hangs (a GDScript compile error leaves a SceneTree running).
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --import > "${TMPDIR:-/tmp}/pinpoint_import.log" 2>&1
rc=0
for t in tests/*_check.gd; do
  log=$(perl -e 'alarm 240; exec @ARGV' godot --headless --path . --script "$t" 2>&1); code=$?
  echo "$log" | grep -v "^Godot Engine" | grep -v "^$"
  if [ $code -ne 0 ] || echo "$log" | grep -q "SCRIPT ERROR"; then echo "RED: $t (exit $code)"; rc=1; fi
done
[ $rc -eq 0 ] && echo GREEN || echo RED
exit $rc
