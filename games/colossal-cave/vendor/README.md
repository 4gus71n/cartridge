# vendor/open-adventure

Unmodified copy of Open Adventure (Colossal Cave Adventure 2.5 in C) by
Eric S. Raymond, BSD-2-Clause (see `open-adventure/COPYING`).

- Upstream: https://gitlab.com/esr/open-adventure
- Pinned commit: `e6160529e70a8c7a06b9a5f190d69aa35c4c62f5` ("Ready to ship 1.22", 2026-07-08)
- Kept: the C sources, `adventure.yaml`, `make_dungeon.py`, `templates/`,
  `COPYING`, `NEWS.adoc`, `README.adoc` and the regression logs in `tests/`.
- Dropped: docs/CI/desktop files, `cheat.c`, and the 15 regression tests that
  exercise SAVE/RESUME, `-l`/`-o` options or save tampering
  (the web build uses `ADVENT_AUTOSAVE`, which disables manual SAVE/RESUME).

To re-vendor: `git clone https://gitlab.com/esr/open-adventure && git -C open-adventure checkout <commit>`,
copy the files above, update the commit here, in `web/LICENSE`, `web/index.html`
(credits) and `CREDITS.md`, then run `tools/build.sh && tools/run_tests.sh`.
