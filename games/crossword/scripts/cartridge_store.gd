class_name CartridgeStore
## Durable saves for games running inside the Cartridge app.
##
## The app exposes `window.cartridge.storage` (getItem / setItem / removeItem),
## backed by Android SharedPreferences / iOS NSUserDefaults, so progress
## survives force-stops, WebView data resets and origin changes. Outside the app
## (desktop, headless tests, a plain browser) this falls back to user:// files,
## so callers never need to care.
##
## Source of truth: games/_shared/cartridge_store.gd, copied into each game by
## tools/sync_shared.sh. Edit it there, not in a game folder.

const PREFIX := "cfg:"

static var _bridge := -1 ## -1 unknown, 0 absent, 1 present


static func has_bridge() -> bool:
	if _bridge == -1:
		_bridge = 0
		if OS.has_feature("web"):
			var ok: Variant = JavaScriptBridge.eval(
				"!!(window.cartridge && window.cartridge.storage)", true)
			# JavaScriptBridge.eval returns a JS boolean as an int (1/0), not a bool.
			_bridge = 1 if (ok is bool and ok) or (ok is int and ok != 0) else 0
	return _bridge == 1


static func _js(expr: String) -> Variant:
	return JavaScriptBridge.eval(expr, true)


static func get_text(key: String) -> Variant:
	if not has_bridge():
		return null
	return _js("window.cartridge.storage.getItem(%s)" % JSON.stringify(key))


static func set_text(key: String, text: String) -> void:
	if has_bridge():
		_js("window.cartridge.storage.setItem(%s, %s)" % [JSON.stringify(key), JSON.stringify(text)])


static func remove_key(key: String) -> void:
	if has_bridge():
		_js("window.cartridge.storage.removeItem(%s)" % JSON.stringify(key))


## Drop-in for `cfg.load(path)`: prefers the app's copy, then the file
## (older saves that only exist in IndexedDB are picked up and kept).
static func load_cfg(cfg: ConfigFile, path: String) -> Error:
	var text: Variant = get_text(PREFIX + path)
	if text is String and text != "":
		return cfg.parse(text)
	return cfg.load(path)


## Drop-in for `cfg.save(path)`: writes the file and the app's copy.
static func save_cfg(cfg: ConfigFile, path: String) -> Error:
	set_text(PREFIX + path, cfg.encode_to_text())
	return cfg.save(path)


static func exists(path: String) -> bool:
	var text: Variant = get_text(PREFIX + path)
	return (text is String and text != "") or FileAccess.file_exists(path)


static func remove(path: String) -> void:
	remove_key(PREFIX + path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
