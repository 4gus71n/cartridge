class_name RunSave
extends RefCounted
## Autosave of the in-progress run (v2 rules), written after every locked
## piece through CartridgeStore. Versioned; anything old/corrupt is discarded.

const PATH := "user://run_v2.cfg"

static var path := PATH


static func save(b: PrismBoard) -> void:
	if b == null or b.state == PrismBoard.State.OVER:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", PrismBoard.SAVE_VERSION)
	cfg.set_value("run", "data", b.to_dict())
	CartridgeStore.save_cfg(cfg, path)


## The saved run, or null (none / unreadable / other version / already lost).
static func load_run() -> PrismBoard:
	if not CartridgeStore.exists(path):
		return null
	var cfg := ConfigFile.new()
	if CartridgeStore.load_cfg(cfg, path) != OK:
		return null
	if int(cfg.get_value("run", "version", 0)) != PrismBoard.SAVE_VERSION:
		return null
	var b := PrismBoard.from_dict(cfg.get_value("run", "data", null))
	if b == null or b.state != PrismBoard.State.PLAYING:
		return null
	return b


static func exists() -> bool:
	return CartridgeStore.exists(path)


static func clear() -> void:
	CartridgeStore.remove(path)
