extends Control
## Pinpoint: one screen script for menu, rounds, reveal, summary and credits.
## Logic lives in plain classes (PinpointGame, PhotoDeck, WorldData, GeoMath)
## so tests can drive it; the UI bot calls the same entry points the
## buttons use (start_game, drop_pin, confirm_guess, next_round, ...).

enum Phase { MENU, GUESS, REVEAL, SUMMARY, CREDITS }

const BG := Color("#0b0e18")
const BG_BOTTOM := Color("#20131a")
const PANEL := Color("#1a2033")
const ACCENT := Color("#ff6b5b")
const ON_ACCENT := Color("#2a0905")
const TEXT := Color("#eef0f6")
const MUTED := Color("#8e94aa")
const GOOD := Color("#3ddc97")
const GOLD := Color("#ffd166")

var phase := Phase.MENU
var game: PinpointGame
var deck: PhotoDeck
var world: WorldData
var paused := false
var record := false
var last_result := {}
var map_big := false

var _menu: Control
var _game: Control
var _summary: Control
var _credits: Control
var _overlay: Control
var _photo: PhotoView
var _map: MapView
var _round_label: Label
var _score_label: Label
var _bottom: VBoxContainer
var _confirm: Button
var _grow: IconButton
var _shown_score := 0.0
var _score_tween: Tween


func _ready() -> void:
	theme = _build_theme()
	_add_background()
	deck = PhotoDeck.load_default()
	world = WorldData.load_default()
	MapView.set_world(world)
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if game != null and phase in [Phase.GUESS, Phase.REVEAL]:
			Settings.save_game(game.to_dict())


func _add_background() -> void:
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, BG)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _clear_screens() -> void:
	_close_overlay()
	for c in [_menu, _game, _summary, _credits]:
		if is_instance_valid(c):
			c.queue_free()
	_menu = null
	_game = null
	_summary = null
	_credits = null
	_photo = null
	_map = null


# --- menu -------------------------------------------------------------------

func has_resume() -> bool:
	var d: Dictionary = Settings.saved_game
	if d.is_empty():
		return false
	var g := PinpointGame.from_dict(d)
	if g.photo_ids.size() != PinpointGame.ROUNDS or g.is_over():
		return false
	for id in g.photo_ids:
		if not deck.by_id.has(id):
			return false
	return true


func show_menu() -> void:
	_clear_screens()
	phase = Phase.MENU
	game = null
	_menu = _margin()
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)

	var frame := _rounded_frame()
	frame.custom_minimum_size = Vector2(0, 400)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	var hero := MapView.new()
	hero.interactive = false
	hero.can_drop = false
	hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(hero)
	for p in deck.photos:
		hero.dots.append(PhotoDeck.geo_of(p))

	box.add_child(_label(tr("TITLE"), 76, ACCENT))
	var sub := _label(tr("SUBTITLE"), 28, TEXT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(_label(tr("HOW"), 22, MUTED))
	box.add_child(_spacer(6))

	if has_resume():
		var g := PinpointGame.from_dict(Settings.saved_game)
		var res := _accent_button(tr("RESUME") % [g.round_index() + 1, PinpointGame.ROUNDS], resume_game)
		res.name = "Resume"
		box.add_child(res)
		var ng := _panel_button(tr("NEW_GAME"), start_game)
		ng.name = "NewGame"
		box.add_child(ng)
	else:
		var play := _accent_button(tr("PLAY"), start_game)
		play.name = "Play"
		box.add_child(play)

	var best := tr("NO_BEST") if Settings.best_score <= 0 else tr("BEST") % GeoMath.group_digits(Settings.best_score)
	box.add_child(_label(best, 28, GOLD))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var units := _flat(tr("UNITS_MI") if Settings.miles else tr("UNITS_KM"))
	units.name = "Units"
	units.pressed.connect(func() -> void:
		Settings.toggle_units()
		show_menu())
	row.add_child(units)
	var lang := _flat(tr("LANGUAGE"))
	lang.name = "Language"
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		show_menu())
	row.add_child(lang)
	var cred := _flat(tr("CREDITS"))
	cred.name = "Credits"
	cred.pressed.connect(show_credits)
	row.add_child(cred)
	for b in row.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# --- game -------------------------------------------------------------------

func start_game(seed_value: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = hash(seed_value)
	else:
		rng.randomize()
	game = PinpointGame.new()
	game.start(deck.pick_round_ids(PinpointGame.ROUNDS, rng, Settings.recent))
	Settings.mark_seen(game.photo_ids)
	Settings.save_game(game.to_dict())
	record = false
	_build_game()
	_begin_round()


func resume_game() -> void:
	game = PinpointGame.from_dict(Settings.saved_game)
	record = false
	_build_game()
	_begin_round()


func _build_game() -> void:
	_clear_screens()
	_game = VBoxContainer.new()
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.add_theme_constant_override("separation", 0)
	add_child(_game)

	var top_m := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		top_m.add_theme_constant_override(k, 14)
	top_m.add_theme_constant_override("margin_top", 8)
	top_m.add_theme_constant_override("margin_bottom", 8)
	_game.add_child(top_m)
	var top := HBoxContainer.new()
	top_m.add_child(top)
	var menu_b := IconButton.new("menu")
	menu_b.name = "Pause"
	menu_b.pressed.connect(pause)
	top.add_child(menu_b)
	_round_label = _label("", 30, TEXT)
	_round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_round_label)
	_score_label = _label("0", 34, GOLD)
	_score_label.custom_minimum_size = Vector2(150, 0)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_score_label)
	top.add_child(_spacer_w(8))

	_photo = PhotoView.new()
	_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game.add_child(_photo)

	var sep := ColorRect.new()
	sep.color = Color(ACCENT, 0.7)
	sep.custom_minimum_size = Vector2(0, 3)
	_game.add_child(sep)

	_map = MapView.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.pin_dropped.connect(func(_g: Vector2) -> void: _update_confirm())
	_game.add_child(_map)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools.position = Vector2(-96, 8)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map.add_child(tools)
	_grow = IconButton.new("grow")
	_grow.name = "Grow"
	_grow.pressed.connect(toggle_map_size)
	tools.add_child(_grow)
	var plus := IconButton.new("plus")
	plus.pressed.connect(func() -> void: _map.zoom_step(1.6))
	tools.add_child(plus)
	var minus := IconButton.new("minus")
	minus.pressed.connect(func() -> void: _map.zoom_step(1.0 / 1.6))
	tools.add_child(minus)

	var bm := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		bm.add_theme_constant_override(k, 22)
	bm.add_theme_constant_override("margin_top", 14)
	bm.add_theme_constant_override("margin_bottom", 22)
	_game.add_child(bm)
	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 6)
	bm.add_child(_bottom)
	_set_map_big(false)


func _begin_round() -> void:
	phase = Phase.GUESS
	var photo: Dictionary = deck.by_id[game.current_id()]
	_round_label.text = tr("ROUND") % [game.round_index() + 1, PinpointGame.ROUNDS]
	_shown_score = game.total()
	_score_label.text = GeoMath.group_digits(game.total())
	_photo.set_texture(deck.load_texture(photo))
	_photo.modulate.a = 0.0
	create_tween().tween_property(_photo, "modulate:a", 1.0, 0.35)
	_map.clear_marks()
	_map.can_drop = true
	_map.reset_view()
	_set_map_big(false)
	for c in _bottom.get_children():
		c.queue_free()
	_confirm = _accent_button(tr("HINT_PLACE"), confirm_guess)
	_confirm.name = "Confirm"
	_bottom.add_child(_confirm)
	_update_confirm()


func _update_confirm() -> void:
	if _confirm == null or not is_instance_valid(_confirm):
		return
	var ready := _map.has_guess
	_confirm.disabled = not ready
	_confirm.text = tr("CONFIRM") if ready else tr("HINT_PLACE")
	_confirm.add_theme_font_size_override("font_size", 38 if ready else 28)
	_confirm.modulate = Color.WHITE if ready else Color(1, 1, 1, 0.55)


## Same as a tap on the map at `geo` (used by the UI bot).
func drop_pin(geo: Vector2) -> void:
	if phase != Phase.GUESS:
		return
	_map.set_guess(geo)
	_update_confirm()


func confirm_guess() -> void:
	if phase != Phase.GUESS or not _map.has_guess:
		return
	var photo: Dictionary = deck.by_id[game.current_id()]
	var truth := PhotoDeck.geo_of(photo)
	var guess_country := world.country_at(_map.guess)
	last_result = game.submit(_map.guess, guess_country, truth, String(photo.country))
	Settings.save_game(game.to_dict())
	phase = Phase.REVEAL
	_set_map_big(true)
	# Let the container settle before framing the line.
	await get_tree().process_frame
	if _map == null:
		return
	_map.reveal(truth, String(photo.country))
	_animate_score(game.total())
	_show_result(photo, last_result)


func _show_result(photo: Dictionary, r: Dictionary) -> void:
	for c in _bottom.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	_bottom.add_child(row)
	var km := float(r.km)
	var dist_text := tr("SPOT_ON") if km < 1.0 else tr("AWAY") % GeoMath.format_distance(km, Settings.miles)
	var dist := _label(dist_text, 36, TEXT)
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dist)
	var pts := _label(tr("POINTS") % GeoMath.group_digits(int(r.points)), 36, GOLD)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pts)
	var lang := Settings.language
	var place := place_name(photo)
	var where := _label(place, 26, TEXT)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bottom.add_child(where)
	var bonus_text: String
	var bonus_col := MUTED
	if r.country_ok:
		bonus_text = tr("COUNTRY_OK") % GeoMath.group_digits(GeoMath.COUNTRY_BONUS)
		bonus_col = GOOD
	elif String(r.guess_country) == "":
		bonus_text = tr("COUNTRY_SEA")
	else:
		bonus_text = tr("COUNTRY_NO") % world.country_name(String(r.guess_country), lang)
	var bonus := _label(bonus_text, 24, bonus_col)
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bonus.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bottom.add_child(bonus)
	var credit := _label(credit_text(photo), 18, MUTED)
	credit.name = "Credit"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.max_lines_visible = 2
	_bottom.add_child(credit)
	var last := game.is_over()
	var next := _accent_button(tr("SEE_RESULTS") if last else tr("NEXT"), next_round)
	next.name = "Next"
	_bottom.add_child(next)
	_bottom.modulate.a = 0.0
	create_tween().tween_property(_bottom, "modulate:a", 1.0, 0.3)


func place_name(photo: Dictionary) -> String:
	var lang := Settings.language
	var country := world.country_name(String(photo.country), lang)
	var place := String(photo.get("place", ""))
	if place == "" or place == country:
		return country
	return "%s, %s" % [place, country]


func credit_text(photo: Dictionary) -> String:
	return tr("PHOTO_BY") % [String(photo.author), String(photo.license)]


func next_round() -> void:
	if phase != Phase.REVEAL:
		return
	if game.is_over():
		show_summary()
	else:
		_begin_round()


func toggle_map_size() -> void:
	_set_map_big(not map_big)


func _set_map_big(big: bool) -> void:
	map_big = big
	if _photo == null:
		return
	_photo.size_flags_stretch_ratio = 0.55 if big else 1.0
	_map.size_flags_stretch_ratio = 1.45 if big else 1.0
	if _grow:
		_grow.kind = "shrink" if big else "grow"


func _animate_score(target: int) -> void:
	if _score_tween:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(func(v: float) -> void:
		_shown_score = v
		if _score_label:
			_score_label.text = GeoMath.group_digits(roundi(v)), _shown_score, float(target), 0.9)


# --- pause ------------------------------------------------------------------

func pause() -> void:
	if phase not in [Phase.GUESS, Phase.REVEAL]:
		return
	paused = true
	var box := _overlay_panel()
	box.add_child(_label(tr("PAUSED"), 48, ACCENT))
	box.add_child(_label(tr("ROUND") % [mini(game.round_index() + 1, PinpointGame.ROUNDS), PinpointGame.ROUNDS], 26, MUTED))
	var cont := _accent_button(tr("CONTINUE"), resume_from_pause)
	cont.name = "Continue"
	box.add_child(cont)
	var leave := _panel_button(tr("SAVE_EXIT"), exit_to_menu)
	leave.name = "SaveExit"
	box.add_child(leave)


func resume_from_pause() -> void:
	paused = false
	_close_overlay()


func exit_to_menu() -> void:
	paused = false
	if game != null and not game.is_over():
		Settings.save_game(game.to_dict())
	show_menu()


# --- summary ----------------------------------------------------------------

func show_summary() -> void:
	var total := game.total()
	record = Settings.submit_score(total)
	Settings.save_game({})
	var finished := game
	_clear_screens()
	game = finished
	phase = Phase.SUMMARY
	_summary = _margin()
	add_child(_summary)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_summary.add_child(box)
	box.add_child(_label(tr("FINAL"), 30, MUTED))
	var big := _label(GeoMath.group_digits(total), 84, GOLD)
	big.name = "Total"
	box.add_child(big)
	big.pivot_offset = Vector2(336, 50)
	big.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(big, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var max_total := PinpointGame.ROUNDS * GeoMath.ROUND_MAX
	box.add_child(_label(tr("OUT_OF") % GeoMath.group_digits(max_total), 24, MUTED))
	if record:
		box.add_child(_label(tr("NEW_BEST"), 32, GOOD))
	else:
		box.add_child(_label(tr("BEST") % GeoMath.group_digits(Settings.best_score), 26, GOLD))

	var frame := _rounded_frame()
	frame.custom_minimum_size = Vector2(0, 360)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	var map := MapView.new()
	map.can_drop = false
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(map)
	_map = map
	var pairs: Array[Dictionary] = []
	for r in finished.results:
		pairs.append({"guess": PinpointGame.guess_of(r), "truth": PinpointGame.truth_of(r)})
	_show_pairs_later(map, pairs)

	for i in finished.results.size():
		var r: Dictionary = finished.results[i]
		var photo: Dictionary = deck.by_id.get(String(r.id), {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var n := _label(str(i + 1), 24, ACCENT)
		n.custom_minimum_size = Vector2(30, 0)
		row.add_child(n)
		var place := _label(place_name(photo) if not photo.is_empty() else "?", 24, TEXT)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		place.clip_text = true
		row.add_child(place)
		var d := _label(GeoMath.format_distance(float(r.km), Settings.miles), 24, MUTED)
		d.custom_minimum_size = Vector2(130, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(d)
		var p := _label(GeoMath.group_digits(int(r.points)), 24, GOOD if r.country_ok else GOLD)
		p.custom_minimum_size = Vector2(90, 0)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(p)

	box.add_child(_spacer(4))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var again := _accent_button(tr("PLAY_AGAIN"), start_game)
	again.name = "PlayAgain"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.size_flags_stretch_ratio = 1.6
	again.add_theme_font_size_override("font_size", 34)
	buttons.add_child(again)
	var menu_b := _panel_button(tr("MENU"), show_menu)
	menu_b.name = "Menu"
	menu_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(menu_b)


func _show_pairs_later(map: MapView, pairs: Array[Dictionary]) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(map):
		map.show_pairs(pairs)


# --- credits ----------------------------------------------------------------

func show_credits() -> void:
	_clear_screens()
	phase = Phase.CREDITS
	_credits = _margin()
	add_child(_credits)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_credits.add_child(box)
	box.add_child(_label(tr("CREDITS_TITLE"), 52, ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	for key in ["CREDITS_CODE", "CREDITS_MAP", "CREDITS_PHOTOS"]:
		var l := _label(tr(key), 24, TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
	var sorted := deck.photos.duplicate()
	sorted.sort_custom(func(a, b): return place_name(a) < place_name(b))
	for p in sorted:
		var l := _label("%s\n%s · %s\n%s" % [place_name(p), String(p.author), String(p.license), String(p.source)], 19, MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		list.add_child(l)
	var back := _panel_button(tr("BACK"), show_menu)
	back.name = "Back"
	box.add_child(back)


# --- overlay + widgets --------------------------------------------------------

func _overlay_panel() -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	panel.pivot_offset = Vector2(300, 200)
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	return box


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func has_overlay() -> bool:
	return _overlay != null


func _rounded_frame() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#08111d")
	sb.set_corner_radius_all(24)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	return p


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 32)
	m.add_theme_constant_override("margin_bottom", 28)
	return m


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _spacer_w(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _accent_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 104)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_stylebox_override("normal", _box(ACCENT))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.15)))
	b.add_theme_stylebox_override("hover_pressed", _box(ACCENT.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", _box(Color("#2a3048")))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ON_ACCENT)
	b.add_theme_color_override("font_disabled_color", TEXT)
	b.pressed.connect(func() -> void: cb.call())
	return b


func _panel_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", 32)
	b.pressed.connect(func() -> void: cb.call())
	return b


func _flat(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", MUTED.lightened(0.25))
	b.add_theme_color_override("font_hover_color", TEXT)
	return b


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	var normal := _box(PANEL)
	normal.border_color = Color(1, 1, 1, 0.08)
	normal.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", _box(PANEL.lightened(0.08)))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.6)))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT.darkened(0.6)))
	t.set_stylebox("disabled", "Button", normal)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.set_color(k, "Button", TEXT)
	var panel := _box(Color("#151a2a"))
	panel.content_margin_left = 32
	panel.content_margin_right = 32
	panel.content_margin_top = 28
	panel.content_margin_bottom = 28
	panel.border_color = Color(ACCENT, 0.45)
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(1, 1, 1, 0.16)
	vs.set_corner_radius_all(4)
	vs.content_margin_left = 6
	t.set_stylebox("grabber", "VScrollBar", vs)
	t.set_stylebox("grabber_highlight", "VScrollBar", vs)
	t.set_stylebox("grabber_pressed", "VScrollBar", vs)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


func _box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb
