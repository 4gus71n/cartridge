#!/bin/bash
# Gate: import + every tests/*_check.gd. RED on non-zero exit or SCRIPT ERROR.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --import > /tmp/minefield_import.log 2>&1
rc=0
for t in tests/*_check.gd; do
  log=$(godot --headless --path . --script "$t" 2>&1); code=$?
  echo "$log"
  if [ $code -ne 0 ] || echo "$log" | grep -q "SCRIPT ERROR"; then echo "RED: $t"; rc=1; fi
done
[ $rc -eq 0 ] && echo GREEN || echo RED
exit $rc
