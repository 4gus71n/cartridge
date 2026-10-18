"""Fixture game packages for the checks tests (built on the fly, served from 127.0.0.1)."""

import zipfile
from pathlib import Path

MIT = """MIT License

Copyright (c) 2026 Test Creator

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
"""

GPL3 = """                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.
"""

APACHE = """                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/
"""

MPL = """Mozilla Public License Version 2.0
==================================
1.12. "Secondary License" means either the GNU General Public License,
Version 2.0, the GNU Lesser General Public License, Version 2.1, the GNU
Affero General Public License, Version 3.0, or any later versions of those
licenses.
"""

INDEX = """<!doctype html><html><head><meta name="viewport" content="width=device-width">
<title>Tap</title></head><body style="margin:0;background:#123">
<canvas id="c" width="412" height="915"></canvas>
<script src="game.js"></script></body></html>"""

GAME_JS = """const ctx = document.getElementById('c').getContext('2d');
ctx.fillStyle = '#7C5CFF'; ctx.fillRect(40, 40, 200, 200);
document.addEventListener('touchstart', () => {});"""

ERROR_JS = "undefinedFunctionCall(); // throws ReferenceError on boot"

CDN_INDEX = """<!doctype html><html><head>
<script src="https://cdn.jsdelivr.net/npm/phaser@3/dist/phaser.min.js"></script>
</head><body><canvas id="c"></canvas><script src="game.js"></script></body></html>"""


def good_files(**extra) -> dict:
    files = {"index.html": INDEX, "game.js": GAME_JS, "LICENSE": MIT}
    files.update(extra)
    return files


def write_zip(path: Path, files: dict, symlinks: dict | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in files.items():
            zf.writestr(name, data)
        for name, target in (symlinks or {}).items():
            info = zipfile.ZipInfo(name)
            info.external_attr = (0o120777 << 16)
            zf.writestr(info, target)
    return path
