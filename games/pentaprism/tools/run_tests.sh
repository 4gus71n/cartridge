#!/bin/bash
# Gate: import + every tests/*_check.gd. RED on non-zero exit or SCRIPT ERROR.
cd "$(dirname "$0")/.." || exit 1
LOGDIR="${TMPDIR:-/tmp}/pentaprism-gate"
mkdir -p "$LOGDIR"
godot --headless --path . --import > "$LOGDIR/import.log" 2>&1
rc=0
for t in tests/*_check.gd; do
  log=$(godot --headless --path . --script "$t" 2>&1); code=$?
  echo "$log"
  if [ $code -ne 0 ] || echo "$log" | grep -qE "SCRIPT ERROR|^ERROR:"; then echo "RED: $t"; rc=1; fi
done
# tests/corrupt_probe.gd feeds broken save files on purpose (the engine logs
# ConfigFile parse ERRORs), so it only fails on a non-zero exit or SCRIPT ERROR.
log=$(godot --headless --path . --script tests/corrupt_probe.gd 2>&1); code=$?
echo "$log" | grep -E "corrupt_probe:|FAIL|SCRIPT ERROR"
if [ $code -ne 0 ] || echo "$log" | grep -q "SCRIPT ERROR"; then echo "RED: tests/corrupt_probe.gd"; rc=1; fi
[ $rc -eq 0 ] && echo GREEN || echo RED
exit $rc
