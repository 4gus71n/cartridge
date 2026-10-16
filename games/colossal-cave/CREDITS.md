# Credits — Colossal Cave / La Cueva Colosal

| Component | Author | License | Source |
|---|---|---|---|
| Colossal Cave Adventure 2.5 (game text, map, puzzles) | Will Crowther (1976) and Don Woods (1977, 1995) | BSD-2-Clause (as released with Open Adventure) | https://gitlab.com/esr/open-adventure |
| Open Adventure (C port: `vendor/open-adventure/`, compiled into `web/advent.wasm`) | Eric S. Raymond and contributors | BSD-2-Clause | https://gitlab.com/esr/open-adventure, pinned commit `e6160529e70a8c7a06b9a5f190d69aa35c4c62f5` (release 1.22, 2026-07-08) |
| Emscripten runtime (`web/advent.js` glue) | Emscripten contributors | MIT / University of Illinois NCSA | https://emscripten.org |
| Web shell, touch controls, autosave, tests (`web/shell.*`, `web/engine.js`, `web/cavetext.js`, `engine/`, `tests/`, `tools/`) | Cartridge Studio | All rights reserved | — |

- Full license texts ship inside the build: `web/LICENSE` (Open Adventure BSD-2 +
  attribution + pin) and `web/LICENSE.emscripten`. The in-game **Menu → Credits &
  license** screen shows the attribution, source URL, commit and the BSD-2 text.
- Modifications to Open Adventure: `engine/web.patch` (calls an autosave hook
  before each command prompt) and `engine/web_shim.c` / `engine/include/`
  (readline replacement that suspends the wasm with Asyncify). Game text and
  logic are unchanged — the upstream regression suite passes byte for byte.
- No fonts, images or audio are bundled (system monospace font, inline SVG icons).
- "Colossal Cave" / "Adventure" are the historical names of a public,
  BSD-licensed work; no trademarked names are used.
