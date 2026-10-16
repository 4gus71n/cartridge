#!/bin/bash
# Gate: node tests driving the Open Adventure wasm build headless
# (engine, save/restore, shell helpers, upstream regression suite) plus a
# static check of the web bundle. Prints GREEN or RED.
cd "$(dirname "$0")/.." || exit 1
command -v node >/dev/null || { echo "node not found"; echo RED; exit 1; }
rc=0

for f in web/index.html web/shell.js web/shell.css web/engine.js web/cavetext.js web/advent.js web/advent.wasm web/LICENSE \
         cartridge.json smoke.json poster.png README.md CREDITS.md; do
  [ -s "$f" ] || { echo "missing or empty: $f"; rc=1; }
done
for f in web/*.js tests/*.js; do
  node --check "$f" || { echo "syntax error: $f"; rc=1; }
done
node -e 'JSON.parse(require("fs").readFileSync("cartridge.json"));JSON.parse(require("fs").readFileSync("smoke.json"))' || rc=1
# offline: no absolute URLs loaded by the page
if grep -nE '(src|href)="(https?:)?//' web/index.html; then echo "index.html references the network"; rc=1; fi

node --test --test-reporter=spec tests/*.test.js 2>&1 | tee "${TMPDIR:-/tmp}/colossal-cave-tests.log" | grep -vE '^\s*✔ regress ' 
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

[ $rc -eq 0 ] && echo GREEN || echo RED
exit $rc
