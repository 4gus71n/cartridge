"""Creator terms shown in the portal. Bump CURRENT_TERMS_VERSION on any change:
creators must accept the new version before submitting again."""

from .config import TAKEDOWN_CONTACT
from .licensing import ALLOWED_LICENSES

CURRENT_TERMS_VERSION = "2026-10-18"

CREATOR_TERMS = f"""Cartridge creator terms (version {CURRENT_TERMS_VERSION})

By submitting a game to Cartridge you confirm that:

1. Your work, your rights. The game is your original work, or you hold the rights
   to every part of it (code, art, sound, music, fonts) and may license it as you
   declare.

2. A permissive license. The game is released under one of these licenses, and the
   package contains the matching LICENSE (or COPYING) file:
   {", ".join(ALLOWED_LICENSES)}.
   GPL-family, share-alike (CC-BY-SA), non-commercial and unlicensed games can't
   be accepted. Cartridge may download, store, re-host and distribute your package
   to players under that license.

3. Safe and respectful. The game contains no malware, crypto mining, tracking or
   analytics, advertising, or data collection, and does not try to escape the
   player's device sandbox. It contains no adult, sexual, hateful or otherwise
   illegal content.

4. Made for phones. The game is playable with touch on a phone screen, without a
   keyboard or mouse, and should work offline once downloaded.

5. Review and removal. Every new game and every update is checked automatically
   and reviewed by a person before players see it. We may reject any submission and
   may remove any game at any time, for example after player reports or a rights
   claim. Approved versions are pinned by checksum: changing the file behind your
   package URL does not change what players get; submit an update instead.

6. Takedown requests. If you believe a game on Cartridge infringes your rights,
   contact us at {TAKEDOWN_CONTACT} and we will act promptly.

We may update these terms; you will be asked to accept the new version before your
next submission.
"""
