extends Control
## Screens: menu, game (HUD + map + action bar) and overlays (pack, map,
## pause, help, log, confirm, death/victory). All rules live in Run; this
## script wires taps/swipes/long-presses to it and autosaves every turn.

const BG := Color("#0b0a10")
const PANEL := Color("#16141f")
const EDGE := Color("#2c283d")
const ACCENT := Color("#ff9e3d")
const TEXT := Color("#ebe6f5")
const MUTED := Color("#9a94ad")
const GOLD := Color("#ffd166")
const DANGER := Color("#ff6b5e")
const MSG_COLORS := [Color("#d9d4e6"), Color("#8fe388"), Color("#ff8a7a"), Color("#ffb45e")]
const MAX_W := 760.0
const TRAVEL_STEP := 0.07
const ACTIONS := ["wait", "search", "grab", "stairs", "pack", "map"]
const ACTION_KEYS := {"wait": "BTN_WAIT", "search": "BTN_SEARCH", "grab": "BTN_GRAB", "stairs": "BTN_STAIRS", "pack": "BTN_PACK", "map": "BTN_MAP"}

var run: Run
var side_margin := 0.0 ## horizontal margin (the poster capture widens it)
var busy := false
var map_view: MapView
var travel: Array = []
var aim_kind := ""
var aim_index := -1
var inv_sel := -1
var last_rank := -1

var _menu: Control
var _menu_col: VBoxContainer
var _play: Control
var _play_col: VBoxContainer
var _depth_label: Label
var _hp_bar: HudBar
var _xp_bar: HudBar
var _lv_label: Label
var _gold_label: Label
var _status_label: Label
var _log_box: VBoxContainer
var _log_panel: PanelContainer
var _inspect: PanelContainer
var _inspect_label: Label
var _aim_bar: PanelContainer
var _aim_label: Label
var _aim_cancel: Button
var _buttons := {} ## action -> Button
var _icons := {} ## action -> ActionIcon
var _btn_labels := {} ## action -> Label
var _overlay: Control
var _overlay_kind := ""
var _gen: Control
var _gen_label: Label
var _travel_t := 0.0
var _travel_alerts := 0
var _armed_at := 0
var _inspect_t := 0.0


func _ready() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_menu = _screen()
	_menu_col = VBoxContainer.new()
	_menu_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_col.add_theme_constant_override("separation", 16)
	_menu.add_child(_menu_col)
	_play = _screen()
	_build_play()
	var gen := ColorRect.new()
	gen.color = Color(BG, 0.94)
	gen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gen = gen
	_gen_label = _label("", 34, ACCENT)
	_gen_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gen_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gen.add_child(_gen_label)
	_gen.visible = false
	add_child(_gen)
	resized.connect(_layout)
	_layout()
	show_menu()


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _layout() -> void:
	var w := minf(size.x - side_margin * 2.0, MAX_W)
	var x := floorf((size.x - w) / 2.0)
	_menu_col.position = Vector2(x + 24, 24)
	_menu_col.size = Vector2(w - 48, size.y - 48)
	_play_col.position = Vector2(x, 0)
	_play_col.size = Vector2(w, size.y)


# --- theme & widget helpers ---------------------------------------------------

func _box(col: Color, radius := 18, border := Color(0, 0, 0, 0), bw := 0, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", _box(Color("#221f2e"), 18, EDGE, 2))
	t.set_stylebox("hover", "Button", _box(Color("#2a2639"), 18, EDGE, 2))
	t.set_stylebox("pressed", "Button", _box(Color("#3a2a1c"), 18, ACCENT, 2))
	t.set_stylebox("disabled", "Button", _box(Color("#18161f"), 18, Color("#1f1c29"), 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("#5c5770"))
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _box(ACCENT, 18))
	t.set_stylebox("hover", "AccentButton", _box(ACCENT.lightened(0.1), 18))
	t.set_stylebox("pressed", "AccentButton", _box(ACCENT.darkened(0.2), 18))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "AccentButton", Color("#1d1206"))
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", _box(Color("#2a1618"), 18, Color("#6b2a2a"), 2))
	t.set_stylebox("hover", "DangerButton", _box(Color("#331a1c"), 18, Color("#6b2a2a"), 2))
	t.set_stylebox("pressed", "DangerButton", _box(Color("#4a1c1c"), 18, DANGER, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(c, "DangerButton", DANGER)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 24, EDGE, 2, 24))
	return t


func _label(text: String, fsize := 28, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, fsize := 26, col := TEXT) -> Label:
	var l := _label(text, fsize, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	return l


func _btn(text: String, node_name: String, cb: Callable, variation := "", h := 96.0) -> Button:
	var b := Button.new()
	b.text = text
	b.name = node_name
	b.custom_minimum_size = Vector2(0, h)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	return b


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# --- menu ---------------------------------------------------------------------

func show_menu() -> void:
	_close_overlay()
	travel.clear()
	_play.visible = false
	_menu.visible = true
	_clear(_menu_col)
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 250)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_menu_art.bind(art))
	_menu_col.add_child(art)
	var title := _label(tr("TITLE"), 104, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(title)
	var sub := _wrap(tr("SUBTITLE"), 26, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(sub)
	_menu_col.add_child(_spacer(10))
	if Settings.has_run():
		var d: Dictionary = Settings.saved_run()
		_menu_col.add_child(_btn(tr("CONTINUE"), "Continue", resume, "AccentButton", 104))
		var info := _label(tr("CONTINUE_INFO").format([d.depth, d.p[4], d.turns]), 22, MUTED)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu_col.add_child(info)
		_menu_col.add_child(_btn(tr("NEW_RUN"), "NewRun", _confirm_new))
	else:
		_menu_col.add_child(_btn(tr("NEW_RUN"), "NewRun", start_new.bind(-1), "AccentButton", 104))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var how := _btn(tr("HOW_TO"), "HowTo", _show_help)
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lang := _btn(tr("LANG_BTN"), "Language", _toggle_language)
	lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(how)
	row.add_child(lang)
	_menu_col.add_child(row)
	_menu_col.add_child(_spacer(8))
	var panel := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_label(tr("HIGH_SCORES"), 26, ACCENT))
	if Settings.scores.is_empty():
		col.add_child(_wrap(tr("NO_SCORES"), 24, MUTED))
	for i in mini(5, Settings.scores.size()):
		var e: Dictionary = Settings.scores[i]
		var r := HBoxContainer.new()
		var n := _label("%d" % (i + 1), 24, MUTED)
		n.custom_minimum_size.x = 34
		r.add_child(n)
		var what := _label(tr("SCORE_ROW").format([e.depth, Txt.render(_short_cause(e))]), 24, GOLD if e.get("won", false) else TEXT)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		r.add_child(what)
		r.add_child(_label(str(e.score), 26, GOLD))
		col.add_child(r)
	if Settings.runs > 0:
		col.add_child(_label(tr("RUNS_LINE").format([Settings.runs, Settings.wins]), 22, MUTED))
	_menu_col.add_child(panel)


static func _short_cause(e: Dictionary) -> String:
	if e.get("won", false):
		return "#VICTORY"
	var c := str(e.get("cause", ""))
	if c == "#CAUSE_QUIT":
		return "#ABANDONED"
	if c.begins_with("#M_"):
		return "#MN_" + c.substr(3)
	if c.begins_with("#CAUSE_"):
		return "#CN_" + c.substr(7)
	return c


func _draw_menu_art(art: Control) -> void:
	# A tiny hand-placed room drawn with the game's own tile palette.
	var rows := ["###########", "#.....g...#", "#.@..!..j.#", "#...$...>.#", "####+######"]
	var ts := minf(60.0, floorf(art.size.x / 11.0))
	var o := Vector2((art.size.x - ts * 11) / 2.0, (art.size.y - ts * 5) / 2.0)
	var font := ThemeDB.fallback_font
	var cols := {"g": Color("#7fd36b"), "!": Color("#ff5a5a"), "j": Color("#5cf28f"), "$": GOLD, ">": ACCENT, "+": MapView.DOOR, "@": MapView.PLAYER}
	art.draw_circle(o + Vector2(2.5, 2.5) * ts, ts * 3.2, Color(ACCENT, 0.06))
	for y in rows.size():
		for x in 11:
			var ch: String = rows[y][x]
			var r := Rect2(o + Vector2(x, y) * ts, Vector2(ts, ts))
			if ch == "#":
				art.draw_rect(r, MapView.WALL_TOP)
				if y == 0:
					art.draw_rect(Rect2(r.position + Vector2(0, ts * 0.62), Vector2(ts, ts * 0.38)), MapView.WALL_FACE)
				continue
			art.draw_rect(r.grow(-1), MapView.FLOOR)
			var c := r.get_center()
			if ch == ".":
				art.draw_circle(c, ts * 0.05, MapView.FLOOR_DOT)
				continue
			var fs := int(ts * 0.62)
			if ch in ["g", "j", "@"]:
				var cc: Color = ACCENT if ch == "@" else cols[ch]
				art.draw_circle(c, ts * 0.42, Color(cc.darkened(0.75), 0.95))
				art.draw_arc(c, ts * 0.42, 0, TAU, 24, Color(cc, 0.8), 2.0, true)
			var base := c + Vector2(-ts * 0.5, (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
			art.draw_string(font, base, ch, HORIZONTAL_ALIGNMENT_CENTER, ts, fs, cols[ch])


func _toggle_language() -> void:
	Settings.set_language("en" if Settings.language == "es" else "es")
	if _menu.visible:
		show_menu()
	else:
		_refresh()


# --- game screen ----------------------------------------------------------------

func _build_play() -> void:
	_play_col = VBoxContainer.new()
	_play_col.add_theme_constant_override("separation", 0)
	_play.add_child(_play_col)
	# HUD
	var hud := PanelContainer.new()
	hud.add_theme_stylebox_override("panel", _box(PANEL, 0, EDGE, 0, 12))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	hud.add_child(hv)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 14)
	var menu_btn := _btn("", "MenuBtn", _show_pause, "", 88)
	menu_btn.custom_minimum_size = Vector2(88, 88)
	var mi := ActionIcon.new()
	mi.kind = "menu"
	mi.set_anchors_preset(Control.PRESET_FULL_RECT)
	mi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_btn.add_child(mi)
	r1.add_child(menu_btn)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	_depth_label = _label("", 28, ACCENT)
	_depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_depth_label)
	_gold_label = _label("", 26, GOLD)
	top.add_child(_gold_label)
	mid.add_child(top)
	_hp_bar = HudBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 38)
	mid.add_child(_hp_bar)
	r1.add_child(mid)
	hv.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 12)
	_lv_label = _label("", 24, TEXT)
	r2.add_child(_lv_label)
	_xp_bar = HudBar.new()
	_xp_bar.color = Color("#7d9cff")
	_xp_bar.custom_minimum_size = Vector2(60, 14)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_xp_bar)
	_status_label = _label("", 24, MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r2.add_child(_status_label)
	hv.add_child(r2)
	_play_col.add_child(hud)
	# Map + overlays on it
	var wrap := Control.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	_play_col.add_child(wrap)
	map_view = MapView.new()
	map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.tapped.connect(_on_tap)
	map_view.swiped.connect(_on_swipe)
	map_view.held.connect(_on_hold)
	wrap.add_child(map_view)
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.035, 0.06, 0.72), 0, Color(0, 0, 0, 0), 0, 12))
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.add_child(_log_box)
	wrap.add_child(_log_panel)
	_inspect = PanelContainer.new()
	_inspect.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.96), 20, ACCENT.darkened(0.3), 2, 18))
	_inspect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_inspect.offset_left = 16
	_inspect.offset_right = -16
	_inspect.offset_bottom = -14
	_inspect.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_label = _wrap("", 26)
	_inspect.add_child(_inspect_label)
	_inspect.visible = false
	wrap.add_child(_inspect)
	_aim_bar = PanelContainer.new()
	_aim_bar.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.97), 20, ACCENT, 3, 14))
	_aim_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_aim_bar.offset_left = 16
	_aim_bar.offset_right = -16
	_aim_bar.offset_bottom = -14
	_aim_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 12)
	_aim_label = _wrap("", 26, ACCENT)
	_aim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aim_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ah.add_child(_aim_label)
	_aim_cancel = _btn("", "AimCancel", _cancel_aim, "", 88)
	_aim_cancel.custom_minimum_size.x = 170
	ah.add_child(_aim_cancel)
	_aim_bar.add_child(ah)
	_aim_bar.visible = false
	wrap.add_child(_aim_bar)
	# Action bar
	var bar_bg := PanelContainer.new()
	bar_bg.add_theme_stylebox_override("panel", _box(PANEL, 0, EDGE, 0, 10))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar_bg.add_child(bar)
	for a in ACTIONS:
		var b := _btn("", "Act_" + a, _on_action.bind(a), "", 112)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(88, 112)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 10
		v.offset_bottom = -8
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := ActionIcon.new()
		ic.kind = a
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var l := _label("", 21, TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		b.add_child(v)
		bar.add_child(b)
		_buttons[a] = b
		_icons[a] = ic
		_btn_labels[a] = l
	_play_col.add_child(bar_bg)
	_play_col.add_child(_spacer(10))


func _show_game() -> void:
	_close_overlay()
	_menu.visible = false
	_play.visible = true
	map_view.run = run
	map_view.snap()


func start_new(seed_value := -1) -> void:
	_close_overlay()
	if busy:
		return
	if seed_value < 0:
		seed_value = Seeds.hash32(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0))
	Settings.clear_run()
	run = null
	map_view.run = null
	_menu.visible = false
	_play.visible = true
	busy = true
	var lv: Level = await _generate(1, seed_value)
	run = Run.create(seed_value, lv)
	busy = false
	_show_game()
	Settings.store_run(run.to_dict())
	_refresh()


func resume() -> void:
	if not Settings.has_run():
		return
	run = Run.from_dict(Settings.saved_run())
	_show_game()
	_refresh()


func _generate(depth: int, seed_value: int) -> Level:
	_gen_label.text = tr("GENERATING").format([depth])
	_gen.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var g := LevelGen.new(depth, seed_value)
	var t0 := Time.get_ticks_msec()
	while not g.step():
		if Time.get_ticks_msec() - t0 > 8:
			await get_tree().process_frame
			t0 = Time.get_ticks_msec()
	_gen.visible = false
	return g.lv


func _refresh() -> void:
	if run == null:
		return
	_depth_label.text = tr("HUD_DEPTH").format([run.depth])
	_gold_label.text = "$ %d" % run.gold
	_hp_bar.color = DANGER if run.hp * 3 < run.mhp else (Color("#e0a040") if run.hp * 3 < run.mhp * 2 else Color("#4fbf6a"))
	_hp_bar.set_value(float(run.hp) / float(run.mhp), "HP %d / %d" % [run.hp, run.mhp])
	_lv_label.text = tr("HUD_LV").format([run.lvl])
	var lo: int = Defs.XP_LEVELS[run.lvl - 1]
	var hi := run.xp_next()
	_xp_bar.set_value(1.0 if hi <= lo else float(run.xp - lo) / float(hi - lo), "")
	var st: Array = []
	var hs := run.hunger_state()
	if hs > 0:
		st.append(tr(["", "H_HUNGRY", "H_WEAK", "H_STARVING"][hs]))
	if run.haste > 0:
		st.append(tr("ST_HASTE"))
	if run.conf > 0:
		st.append(tr("ST_CONF"))
	if run.pois > 0:
		st.append(tr("ST_POIS"))
	_status_label.text = " · ".join(st)
	_status_label.add_theme_color_override("font_color", DANGER if hs >= 2 or run.pois > 0 else (Color("#ffb45e") if not st.is_empty() else MUTED))
	# Message log: last 3 lines, older ones dimmer.
	_clear(_log_box)
	var n := run.msgs.size()
	var shown := run.msgs.slice(maxi(0, n - 3))
	for e in shown:
		var l := _wrap(Txt.sentence(e.m), 24, MSG_COLORS[int(e.k)])
		var age := run.turns - int(e.t)
		l.modulate.a = 1.0 if age <= 0 else (0.75 if age <= 3 else 0.5)
		_log_box.add_child(l)
	_log_panel.visible = shown.size() > 0
	for a in ACTIONS:
		(_btn_labels[a] as Label).text = tr(ACTION_KEYS[a])
	var can_grab := not run.lv.items_at(run.px, run.py).is_empty()
	var on_stairs := run.on_stairs()
	_set_enabled("grab", can_grab, can_grab)
	_set_enabled("stairs", on_stairs, on_stairs)
	_aim_cancel.text = tr("CANCEL")
	map_view.consume_events()
	map_view.queue_redraw()


func _set_enabled(a: String, on: bool, glow: bool) -> void:
	var b: Button = _buttons[a]
	b.disabled = not on
	var ic: ActionIcon = _icons[a]
	ic.color = ACCENT if glow else (TEXT if on else Color("#4d485e"))
	ic.queue_redraw()
	(_btn_labels[a] as Label).add_theme_color_override("font_color", ACCENT if glow else (TEXT if on else Color("#5c5770")))


# --- turn flow ------------------------------------------------------------------

func can_act() -> bool:
	return run != null and run.state == "play" and not busy and _play.visible and _overlay == null


func do_action(f: Callable) -> bool:
	if not can_act():
		return false
	_hide_inspect()
	var took: bool = f.call()
	await _after_action()
	return took


func _after_action() -> void:
	if run.pending_descend:
		travel.clear()
		busy = true
		map_view.consume_events()
		var lv: Level = await _generate(run.depth + 1, run.run_seed)
		run.enter_level(lv)
		map_view.snap()
		busy = false
	if run.state != "play":
		travel.clear()
		_refresh()
		_end_run()
		return
	Settings.store_run(run.to_dict())
	_refresh()


func _on_action(a: String) -> void:
	travel.clear()
	if run == null:
		return
	match a:
		"wait":
			do_action(run.act_wait)
		"search":
			do_action(_search_burst)
		"grab":
			do_action(run.act_pickup)
		"stairs":
			do_action(run.act_descend)
		"pack":
			if can_act():
				show_inventory()
		"map":
			if can_act():
				show_map()


## Searches up to 5 turns, stopping early when something happens.
func _search_burst() -> bool:
	var a0 := run.alerts
	for i in 5:
		run.act_search()
		if run.alerts != a0 or run.state != "play":
			break
	return true


func _on_tap(cell: Vector2i) -> void:
	if run == null or busy:
		return
	if aim_kind != "":
		_aim_at(cell)
		return
	if _inspect.visible:
		_hide_inspect()
	travel.clear()
	var me := Vector2i(run.px, run.py)
	if cell == me:
		if not run.lv.items_at(me.x, me.y).is_empty():
			do_action(run.act_pickup)
		elif run.on_stairs():
			do_action(run.act_descend)
		else:
			do_action(run.act_wait)
		return
	var d := cell - me
	if Run.cheb(d.x, d.y) == 1:
		do_action(run.act_move.bind(d))
		return
	travel_to(cell)


func travel_to(cell: Vector2i) -> bool:
	var me := Vector2i(run.px, run.py)
	var blocked := {}
	for m in run.lv.monsters:
		if run.can_see(m) and Vector2i(m.x, m.y) != cell:
			blocked[Level.idx(m.x, m.y)] = true
	for i in run.lv.traps:
		if run.lv.traps[i].f and i != Level.idx(cell.x, cell.y):
			blocked[i] = true
	var path := Pathing.find_path(run.lv, me, cell, true, blocked)
	if path.is_empty():
		return false
	travel = path
	_travel_alerts = run.alerts
	_travel_t = TRAVEL_STEP
	return true


func travel_step() -> void:
	if travel.is_empty() or not can_act():
		travel.clear()
		return
	var me := Vector2i(run.px, run.py)
	var next: Vector2i = travel[0]
	var d := next - me
	if Run.cheb(d.x, d.y) != 1:
		travel.clear()
		return
	if not run.lv.monster_at(next.x, next.y).is_empty() and travel.size() > 1:
		travel.clear()
		return
	await do_action(run.act_move.bind(d))
	if run == null or travel.is_empty():
		return
	if Vector2i(run.px, run.py) == next:
		travel.pop_front()
	elif run.lv.tile(next.x, next.y) != Level.OPEN_DOOR:
		travel.clear()
	if run.alerts != _travel_alerts or run.state != "play":
		travel.clear()
		return
	for o in run.lv.monsters:
		if run.can_see_cell(o.x, o.y) and o.aw and int(o.sl) == 0 and Run.cheb(o.x - run.px, o.y - run.py) <= 2:
			travel.clear()
			return


func _process(delta: float) -> void:
	if not travel.is_empty():
		_travel_t += delta
		if _travel_t >= TRAVEL_STEP:
			_travel_t = 0.0
			travel_step()
	if _inspect.visible:
		_inspect_t -= delta
		if _inspect_t <= 0.0:
			_hide_inspect()


func _on_swipe(dir: Vector2i) -> void:
	if aim_kind != "" or run == null:
		return
	travel.clear()
	do_action(run.act_move.bind(dir))


func _on_hold(cell: Vector2i) -> void:
	if run == null:
		return
	travel.clear()
	var lines: Array = []
	for s in run.describe(cell.x, cell.y):
		lines.append(Txt.sentence(s))
	_inspect_label.text = "\n".join(lines)
	_inspect.visible = true
	_inspect_t = 3.5


func inspect_text() -> String:
	return _inspect_label.text if _inspect.visible else ""


func _hide_inspect() -> void:
	_inspect.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or not can_act():
		return
	var k: int = event.keycode
	var dirs := {KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1), KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0),
		KEY_KP_8: Vector2i(0, -1), KEY_KP_2: Vector2i(0, 1), KEY_KP_4: Vector2i(-1, 0), KEY_KP_6: Vector2i(1, 0),
		KEY_KP_7: Vector2i(-1, -1), KEY_KP_9: Vector2i(1, -1), KEY_KP_1: Vector2i(-1, 1), KEY_KP_3: Vector2i(1, 1)}
	if dirs.has(k):
		_on_swipe(dirs[k])
	elif k == KEY_SPACE or k == KEY_PERIOD or k == KEY_KP_5:
		_on_action("wait")
	elif k == KEY_G or k == KEY_COMMA:
		_on_action("grab")
	elif k == KEY_ENTER or k == KEY_GREATER:
		_on_action("stairs")
	elif k == KEY_I:
		_on_action("pack")
	elif k == KEY_M:
		_on_action("map")
	else:
		return
	get_viewport().set_input_as_handled()


# --- aiming -------------------------------------------------------------------------

func _start_aim(kind: String, i: int) -> void:
	_close_overlay()
	inv_sel = -1
	aim_kind = kind
	aim_index = i
	_aim_label.text = tr("AIM_THROW" if kind == "throw" else "AIM_ZAP")
	_aim_bar.visible = true
	map_view.aiming = true
	map_view.queue_redraw()


func _cancel_aim() -> void:
	aim_kind = ""
	aim_index = -1
	_aim_bar.visible = false
	map_view.aiming = false
	map_view.queue_redraw()


func _aim_at(cell: Vector2i) -> void:
	if cell == Vector2i(run.px, run.py):
		return
	var kind := aim_kind
	var i := aim_index
	_cancel_aim()
	if kind == "throw":
		do_action(run.act_throw.bind(i, cell))
	else:
		do_action(run.act_zap.bind(i, cell))


# --- overlays -------------------------------------------------------------------------

func _open_overlay(kind: String, content: Control, width_frac := 0.92, tap_close := false) -> PanelContainer:
	_close_overlay()
	travel.clear()
	_hide_inspect()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if tap_close:
		dim.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and not ev.pressed:
				_close_overlay())
	add_child(dim)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS if tap_close else Control.MOUSE_FILTER_STOP
	panel.add_child(content)
	dim.add_child(panel)
	var w := minf(size.x - side_margin * 2.0, MAX_W) * width_frac
	panel.custom_minimum_size.x = w
	panel.position = Vector2((size.x - w) / 2.0, 0)
	var center := func() -> void:
		if is_instance_valid(panel):
			panel.position = Vector2((size.x - panel.size.x) / 2.0, maxf(20.0, (size.y - panel.size.y) / 2.0))
	panel.resized.connect(center)
	# Autowrapped labels over-report height on the first layout pass; shrink once
	# the width is known so dialogs hug their content.
	var fit := func() -> void:
		if is_instance_valid(panel):
			panel.reset_size()
			center.call()
	fit.call_deferred()
	panel.minimum_size_changed.connect(func() -> void: fit.call_deferred())
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.15)
	_overlay = dim
	_overlay_kind = kind
	return panel


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_overlay_kind = ""


func overlay_kind() -> String:
	return _overlay_kind


func overlay_node() -> Control:
	return _overlay


func _title_row(text: String, col := ACCENT) -> HBoxContainer:
	var h := HBoxContainer.new()
	var t := _label(text, 34, col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	var x := _btn(tr("CLOSE"), "Close", _close_overlay, "", 88)
	x.custom_minimum_size.x = 150
	h.add_child(x)
	return h


func show_inventory() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_title_row(tr("PACK_TITLE").format([run.inv.size(), Run.INV_MAX])))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(size.y * 0.5, 86.0 * run.inv.size()))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	v.add_child(sc)
	if inv_sel >= run.inv.size():
		inv_sel = -1
	for i in run.inv.size():
		list.add_child(_inv_row(i))
	var detail := VBoxContainer.new()
	detail.name = "Detail"
	detail.add_theme_constant_override("separation", 10)
	v.add_child(detail)
	_open_overlay("inventory", v)
	_fill_detail(detail)


func _inv_row(i: int) -> Button:
	var it: Dictionary = run.inv[i]
	var b := Button.new()
	b.name = "Item%d" % i
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 80)
	if i == inv_sel:
		b.add_theme_stylebox_override("normal", _box(Color("#2e2416"), 16, ACCENT, 2))
	b.pressed.connect(select_item.bind(i))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -18
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := _label(Run.item_glyph(it), 40, run.item_color(it))
	g.custom_minimum_size.x = 36
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g.size_flags_vertical = Control.SIZE_FILL
	h.add_child(g)
	var n := _label(Txt.cap(Txt.render(run.item_name(it))), 26, TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_FILL
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(n)
	if it.q:
		var e := _label(tr("EQUIPPED"), 22, ACCENT)
		e.size_flags_vertical = Control.SIZE_FILL
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(e)
	b.add_child(h)
	return b


func select_item(i: int) -> void:
	inv_sel = i
	show_inventory()


func _fill_detail(detail: VBoxContainer) -> void:
	if inv_sel < 0:
		detail.add_child(_wrap(tr("PACK_HINT"), 24, MUTED))
		return
	var it: Dictionary = run.inv[inv_sel]
	detail.add_child(_wrap(Txt.cap(Txt.render(run.item_name(it))), 30, run.item_color(it).lerp(TEXT, 0.4)))
	for s in run.item_info(it):
		detail.add_child(_wrap(Txt.sentence(s), 24, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var c := Defs.cls(it.id)
	var primary := ""
	match c:
		"potion":
			primary = "ACT_QUAFF"
		"scroll":
			primary = "ACT_READ"
		"food":
			primary = "ACT_EAT"
		"wand":
			primary = "ACT_ZAP"
		"weapon":
			primary = "ACT_REMOVE" if it.q else "ACT_WIELD"
		"armour":
			primary = "ACT_REMOVE" if it.q else "ACT_WEAR"
	var i := inv_sel
	if primary != "":
		var pb := _btn(tr(primary), "ActPrimary", _inv_primary.bind(i), "AccentButton", 92)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pb)
	if c != "armour":
		var tb := _btn(tr("ACT_THROW"), "ActThrow", _start_aim.bind("throw", i), "", 92)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tb)
	var db := _btn(tr("ACT_DROP"), "ActDrop", _inv_drop.bind(i), "", 92)
	db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(db)
	detail.add_child(row)


func _inv_primary(i: int) -> void:
	var it: Dictionary = run.inv[i]
	if Defs.cls(it.id) == "wand":
		_start_aim("zap", i)
		return
	_close_overlay()
	inv_sel = -1
	var took: bool = await do_action(run.act_use.bind(i))
	if not took:
		_refresh()


func _inv_drop(i: int) -> void:
	_close_overlay()
	inv_sel = -1
	do_action(run.act_drop.bind(i))


func show_map() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label(tr("MAP_TITLE").format([run.depth]), 34, ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var mm := MiniMap.new()
	mm.run = run
	var w := minf(size.x - side_margin * 2.0, MAX_W) * 0.92 - 48
	mm.custom_minimum_size = Vector2(w, minf(w * Level.H / Level.W, size.y * 0.7))
	mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mm)
	var hint := _label(tr("TAP_CLOSE"), 22, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	_open_overlay("map", v, 0.92, true)


func _show_pause() -> void:
	if run == null or busy:
		return
	_cancel_aim()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var t := _label(tr("PAUSED"), 38, ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := _label(tr("SEED").format([Seeds.code(run.run_seed)]), 22, MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(_btn(tr("MENU_RESUME"), "Resume", _close_overlay, "AccentButton"))
	v.add_child(_btn(tr("MENU_LOG"), "Log", _show_log))
	v.add_child(_btn(tr("HOW_TO"), "HowTo", _show_help))
	v.add_child(_btn(tr("LANG_BTN"), "Language", func() -> void:
		_toggle_language()
		_show_pause()))
	v.add_child(_btn(tr("MENU_MAIN"), "ToMenu", show_menu))
	v.add_child(_btn(tr("MENU_ABANDON"), "Abandon", _confirm.bind(tr("CONFIRM_ABANDON"), abandon), "DangerButton"))
	_open_overlay("pause", v, 0.8)


func _show_log() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_title_row(tr("LOG_TITLE")))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, size.y * 0.62)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if run != null:
		for e in run.msgs:
			list.add_child(_wrap(Txt.sentence(e.m), 24, MSG_COLORS[int(e.k)]))
	v.add_child(sc)
	_open_overlay("log", v)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _show_help() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_title_row(tr("HELP_TITLE")))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(size.y * 0.66, 900.0))
	var body := _wrap(tr("HELP_BODY"), 26)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	v.add_child(sc)
	_open_overlay("help", v)


func _confirm(text: String, on_yes: Callable) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	var l := _wrap(text, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var no := _btn(tr("NO"), "No", _close_overlay)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var yes := _btn(tr("YES"), "Yes", func() -> void:
		_close_overlay()
		on_yes.call(), "DangerButton")
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(no)
	h.add_child(yes)
	v.add_child(h)
	_open_overlay("confirm", v, 0.82)


func _confirm_new() -> void:
	_confirm(tr("CONFIRM_NEW"), start_new.bind(-1))


func abandon() -> void:
	if run == null or run.state != "play":
		return
	run.state = "dead"
	run.cause = "#CAUSE_QUIT"
	_end_run()


# --- end of run ---------------------------------------------------------------------------

func _end_run() -> void:
	_cancel_aim()
	Settings.clear_run()
	var entry := {"score": run.score(), "depth": run.depth, "turns": run.turns, "lvl": run.lvl,
		"won": run.state == "won", "cause": run.cause, "code": Seeds.code(run.run_seed)}
	last_rank = Settings.add_score(entry)
	_show_end()


func _show_end() -> void:
	var won := run.state == "won"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var t := _label(tr("WIN_TITLE" if won else "DEATH_TITLE"), 56, GOLD if won else DANGER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var cause_text := ""
	if won:
		cause_text = tr("WIN_CAUSE")
	elif str(run.cause) == "#CAUSE_QUIT":
		cause_text = tr("QUIT_CAUSE").format([run.depth])
	else:
		cause_text = Txt.sentence({"f": "DEATH_CAUSE", "a": [run.cause, run.depth]})
	var c := _wrap(cause_text, 28)
	c.name = "Cause"
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for pair in [["STAT_DEPTH", str(run.deepest)], ["STAT_LEVEL", str(run.lvl)], ["STAT_TURNS", str(run.turns)],
			["STAT_KILLS", str(run.kills)], ["STAT_GOLD", str(run.gold)]]:
		var k := _label(tr(pair[0]), 26, MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var val := _label(pair[1], 26, TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
	var gc := MarginContainer.new()
	gc.add_theme_constant_override("margin_left", 30)
	gc.add_theme_constant_override("margin_right", 30)
	gc.add_child(grid)
	v.add_child(gc)
	var sc := _label("%s  %d" % [tr("STAT_SCORE"), run.score()], 44, GOLD)
	sc.name = "Score"
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sc)
	if last_rank == 0:
		var nr := _label(tr("NEW_RECORD"), 30, ACCENT)
		nr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nr)
	elif last_rank > 0:
		var rk := _label(tr("RANKED").format([last_rank + 1]), 24, MUTED)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rk)
	var sd := _label(tr("SEED").format([Seeds.code(run.run_seed)]), 22, MUTED)
	sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sd)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var menu_b := _btn(tr("MENU_BTN"), "EndMenu", end_button.bind(false))
	menu_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var again := _btn(tr("NEW_RUN"), "EndNew", end_button.bind(true), "AccentButton")
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(menu_b)
	h.add_child(again)
	v.add_child(h)
	_armed_at = Time.get_ticks_msec() + 700
	var p := _open_overlay("end", v, 0.9)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(p, "modulate:a", 1.0, 0.4)


func end_button(again: bool, force := false) -> void:
	if Time.get_ticks_msec() < _armed_at and not force:
		return
	run = null
	map_view.run = null
	if again:
		start_new(-1)
	else:
		show_menu()
