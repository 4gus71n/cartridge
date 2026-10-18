"""License allow-list (roadmap §3) and a small SPDX detector for LICENSE texts."""

import re

# Permissive licenses we can redistribute inside the app.
ALLOWED_LICENSES = (
    "MIT",
    "ISC",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "Apache-2.0",
    "MPL-2.0",
    "Unlicense",
    "CC0-1.0",
    "CC-BY-4.0",
)
_CANONICAL = {spdx.lower(): spdx for spdx in ALLOWED_LICENSES}


def canonical_spdx(value: str) -> str:
    """Case-insensitive match against the allow-list; returns the input if unknown."""
    value = (value or "").strip()
    return _CANONICAL.get(value.lower(), value)


def is_allowed(spdx: str) -> bool:
    return canonical_spdx(spdx) in ALLOWED_LICENSES


def detect_spdx(text: str) -> str | None:
    """Best-effort SPDX id from a license file's text (None when unrecognised).

    Order matters: MPL-2.0 mentions the GNU licenses (secondary licenses) and the
    LGPL/AGPL texts mention the GPL, so the more specific texts are tested first.
    """
    t = " ".join((text or "").split()).lower()
    if not t:
        return None
    if "mozilla public license" in t and "2.0" in t:
        return "MPL-2.0"
    if "gnu affero general public license" in t:
        return "AGPL-3.0"
    if "gnu lesser general public license" in t or "gnu library general public license" in t:
        return "LGPL-3.0" if "version 3" in t else "LGPL-2.1"
    if "gnu general public license" in t:
        return "GPL-3.0" if "version 3" in t else "GPL-2.0"
    if "apache license" in t and "version 2.0" in t:
        return "Apache-2.0"
    if "free and unencumbered software released into the public domain" in t:
        return "Unlicense"
    if "cc0 1.0" in t or "creative commons zero" in t or "creative commons legal code cc0" in t:
        return "CC0-1.0"
    if "attribution-noncommercial" in t or "attribution-non-commercial" in t:
        return "CC-BY-NC-4.0"
    if "attribution-sharealike" in t or "attribution-share alike" in t:
        return "CC-BY-SA-4.0"
    if "attribution-noderivatives" in t or "attribution-noderivs" in t:
        return "CC-BY-ND-4.0"
    if re.search(r"creative commons attribution 4\.0|attribution 4\.0 international", t):
        return "CC-BY-4.0"
    if "permission is hereby granted, free of charge" in t:
        return "MIT"
    if re.search(
        r"permission to use, copy, modify, and(/or)? distribute this software for any purpose", t
    ):
        return "ISC"
    if "redistribution and use in source and binary forms" in t:
        if "neither the name" in t or "endorse or promote" in t:
            return "BSD-3-Clause"
        return "BSD-2-Clause"
    return None
