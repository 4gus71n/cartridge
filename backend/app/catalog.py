"""Public catalog published to GitHub Pages (catalog.json + config.json).

Contract for other modules: anything that changes what players should see
(approving a version, a takedown, a sync of originals) calls `request_publish()`.
The catalog is built from `games` rows: status == "verified" → listed,
status == "taken_down" → listed with takenDown=true so apps delete local copies.
Phase 1 fills in the real implementation; until then this is a no-op hook.
"""

import logging

log = logging.getLogger("cartridge.catalog")


def request_publish(reason: str = "") -> None:
    log.info("catalog publish requested: %s", reason)
