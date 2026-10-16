#!/bin/bash
# Build Colossal Cave for the web and fill export/web/.
#
# If emcc is available: compile vendor/open-adventure (pinned upstream source)
# + engine/web.patch + engine/web_shim.c to web/advent.js + web/advent.wasm.
# Without emcc: reuse the committed web/advent.{js,wasm}.
# Then copy web/ to export/web/ (index.html, js, wasm, LICENSE, ...).
#
#   tools/build.sh            # compile if possible, then export
#   tools/build.sh --no-emcc  # just export the committed build
set -euo pipefail
cd "$(dirname "$0")/.."
GAME=$(pwd)
VERSION=1.22

if [ "${1:-}" != "--no-emcc" ] && command -v emcc >/dev/null 2>&1; then
  WORK="${TMPDIR:-/tmp}/colossal-cave-build-$$"
  rm -rf "$WORK"; mkdir -p "$WORK"
  trap 'rm -rf "$WORK"' EXIT
  cp -R vendor/open-adventure "$WORK/src"
  rm -rf "$WORK/src/tests"
  (cd "$WORK/src" && patch -s -p1 < "$GAME/engine/web.patch")

  # make_dungeon.py needs PyYAML; use a throwaway venv if the system lacks it.
  PY=python3
  if ! "$PY" -c 'import yaml' 2>/dev/null; then
    VENV="${TMPDIR:-/tmp}/colossal-cave-pyyaml-venv"
    [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
    "$VENV/bin/python" -c 'import yaml' 2>/dev/null || "$VENV/bin/pip" install -q pyyaml
    PY="$VENV/bin/python"
  fi
  (cd "$WORK/src" && "$PY" make_dungeon.py)

  SRC="$WORK/src"
  emcc -std=gnu99 -O2 -D_DEFAULT_SOURCE -DVERSION="\"$VERSION\"" -DADVENT_AUTOSAVE \
    -I"$GAME/engine/include" -I"$SRC" \
    "$SRC/main.c" "$SRC/init.c" "$SRC/actions.c" "$SRC/score.c" "$SRC/misc.c" \
    "$SRC/saveresume.c" "$SRC/dungeon.c" "$GAME/engine/web_shim.c" \
    -sASYNCIFY=1 -sMODULARIZE=1 -sEXPORT_NAME=createAdvent \
    -sENVIRONMENT=web,node -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1 \
    -sEXPORTED_RUNTIME_METHODS=FS \
    -sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8' \
    -o "$GAME/web/advent.js"
  echo "compiled web/advent.js + web/advent.wasm with $(emcc --version 2>/dev/null | head -1)"
else
  echo "emcc not used: exporting the committed web/advent.{js,wasm}"
fi

for f in index.html shell.js shell.css engine.js cavetext.js advent.js advent.wasm LICENSE LICENSE.emscripten; do
  [ -f "web/$f" ] || { echo "missing web/$f" >&2; exit 1; }
done
rm -rf export/web
mkdir -p export
cp -R web export/web
echo "export/web: $(ls export/web | tr '\n' ' ')($(du -sk export/web | cut -f1) KB)"
