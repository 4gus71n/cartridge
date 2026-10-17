extends Control
## Screens: menu, game (board + tools + number pad) and the win overlay.
## All rules live in SudokuGame; this script only wires taps to it.

const BG := Color("#0b0e18")
const PANEL := Color("#151a2c")
const EDGE := Color("#2b3352")
const ACCENT := BoardView.ACCENT
const TEXT := BoardView.TEXT
const MUTED := BoardView.MUTED
const DARK := Color("#1a1205")
const MAX_W := 760.0
const SAVE_EVERY := 5.0
const TOOLS := ["undo", "erase", "notes", "hint", "check"]
const TOOL_KEYS := {"undo": "UNDO", "erase": "ERASE", "notes": "NOTES", "hint": "HINT", "check": "CHECK"}

var game: SudokuGame
var board: BoardView
var notes_mode := false
var side_margin := 18.0 ## horizontal screen margin (the poster capture widens it)
var _menu: Control
var _menu_col: VBoxContainer
var _play: Control
var _play_col: VBoxContainer
var _title_label: Label
var _stats_label: Label
var _timer_label: Label
var _toast: Label
var _toast_tw: Tween
var _keys := {} ## digit -> PadKey
var _tools := {} ## name -> PadKey
var _row2: HBoxContainer
var _overlay: Control
var _win_box: VBoxContainer
var _save_t := 0.0
var _shown_sec := -1
var _win_armed_at := 0 ## msec; win buttons ignore taps until then (rapid pad taps)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_menu = _screen()
	_menu_col = VBoxContainer.new()
	_menu_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_col.add_theme_constant_override("separation", 18)
	_menu.add_child(_menu_col)
	_play = _screen()
	_build_play()
	_build_overlay()
	resized.connect(_layout)
	show_menu()


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# --- layout -----------------------------------------------------------------

func _layout() -> void:
	var w := minf(size.x - side_margin * 2.0, MAX_W)
	var x := floorf((size.x - w) / 2.0)
	_menu_col.position = Vector2(x, 24)
	_menu_col.size = Vector2(w, size.y - 48)
	_play_col.position = Vector2(x, 14)
	_play_col.size = Vector2(w, size.y - 28)
	# Board: as large as the width allows, but never squeezing the controls.
	var sep := 12.0
	var fixed := 92.0 + 34.0 + 104.0 + 108.0 * 2.0 + sep * 7.0
	board.custom_minimum_size = Vector2(0, clampf(size.y - 28.0 - fixed, 420.0, w))
	var key_w := floorf((w - 4.0 * 10.0) / 5.0)
	for d in range(6, 10):
		_keys[d].custom_minimum_size.x = key_w
	if _overlay:
		_win_box.get_parent().custom_minimum_size.x = minf(w, 600.0)


# --- widgets ------------------------------------------------------------------

func _label(text: String, fs: int, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 600 # sane min height before the first layout pass
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(col: Color, radius := 22, border := EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _style(b: Button, primary := false, fs := 30) -> void:
	var base := ACCENT if primary else PANEL
	var border := Color(0, 0, 0, 0) if primary else EDGE
	b.add_theme_stylebox_override("normal", _box(base, 22, border))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.06), 22, border))
	b.add_theme_stylebox_override("pressed", _box(base.darkened(0.18), 22, ACCENT))
	b.add_theme_stylebox_override("disabled", _box(base.darkened(0.25), 22, border))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", fs)
	var fc := DARK if primary else TEXT
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fc)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.focus_mode = Control.FOCUS_NONE


## Two-line card button (title + sub line).
func _card(title: String, sub: String, primary := false, h := 112.0) -> Button:
	var b := Button.new()
	_style(b, primary)
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_label(title, 32, DARK if primary else TEXT))
	if sub != "":
		v.add_child(_label(sub, 22, Color(DARK, 0.75) if primary else MUTED))
	b.add_child(v)
	return b


func _key(digit: int, icon := "", caption := "") -> PadKey:
	var k := PadKey.new()
	k.digit = digit
	k.icon_name = icon
	k.caption = caption
	_style(k)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.custom_minimum_size = Vector2(0, 108 if digit > 0 else 104)
	return k


static func fmt_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


static func level_name(lv: int) -> String:
	return TranslationServer.translate(["", "EASY", "MEDIUM", "HARD"][clampi(lv, 1, 3)])


func _game_title(lv: int, day: int) -> String:
	return tr("LEVEL_DAILY") % level_name(lv) if day >= 0 else level_name(lv)


# --- menu -----------------------------------------------------------------------

func show_menu() -> void:
	_save_game()
	game = null
	_overlay.visible = false
	_play.visible = false
	_menu.visible = true
	for c in _menu_col.get_children():
		_menu_col.remove_child(c)
		c.queue_free()
	var title := _label(tr("TITLE"), 88, ACCENT)
	_menu_col.add_child(title)
	_menu_col.add_child(_label(tr("SUBTITLE"), 26, MUTED, true))
	var art := MenuArt.new()
	art.custom_minimum_size = Vector2(0, 300)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_col.add_child(art)
	var today := SudokuGame.today()
	var saved: Dictionary = Settings.saved_game
	if not saved.is_empty():
		var sub := "%s  ·  %s" % [_game_title(int(saved.get("level", 2)), int(saved.get("daily_day", -1))),
			fmt_time(float(saved.get("elapsed", 0.0)))]
		var cont := _card(tr("CONTINUE"), sub, true)
		cont.name = "Continue"
		cont.pressed.connect(continue_game)
		_menu_col.add_child(cont)
	var done := Settings.daily_done(today)
	var dsub: String = tr("DAILY_DONE") if done else tr("STREAK_LINE") % Settings.current_streak(today)
	var daily := _card(tr("DAILY"), dsub, saved.is_empty() and not done)
	daily.name = "Daily"
	daily.disabled = done
	daily.pressed.connect(start_daily)
	_menu_col.add_child(daily)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for lv in [1, 2, 3]:
		var best: float = Settings.best_times[lv]
		var b := _card(level_name(lv), tr("BEST") % fmt_time(best) if best > 0.0 else tr("NO_BEST"), false, 120)
		b.name = "Level%d" % lv
		b.pressed.connect(start_game.bind(lv))
		row.add_child(b)
	_menu_col.add_child(row)
	_menu_col.add_child(_label(tr("HOW_TO"), 23, MUTED, true))
	var lang := Button.new()
	lang.text = tr("LANGUAGE")
	lang.name = "Language"
	_style(lang, false, 26)
	lang.custom_minimum_size = Vector2(260, 88)
	lang.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		show_menu())
	_menu_col.add_child(lang)
	_layout()
	_layout.call_deferred()


# --- game screen ------------------------------------------------------------------

func _build_play() -> void:
	_play_col = VBoxContainer.new()
	_play_col.add_theme_constant_override("separation", 12)
	_play.add_child(_play_col)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 92)
	var back := _key(0, "back", "")
	back.name = "Back"
	back.size_flags_horizontal = Control.SIZE_FILL
	back.custom_minimum_size = Vector2(120, 92)
	back.pressed.connect(show_menu)
	top.add_child(back)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	_title_label = _label("", 32, TEXT)
	_stats_label = _label("", 21, MUTED)
	mid.add_child(_title_label)
	mid.add_child(_stats_label)
	top.add_child(mid)
	_timer_label = _label("0:00", 36, ACCENT)
	_timer_label.custom_minimum_size = Vector2(120, 0)
	top.add_child(_timer_label)
	_play_col.add_child(top)
	var spacer_a := Control.new()
	spacer_a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_col.add_child(spacer_a)
	_toast = _label("", 24, MUTED)
	_toast.custom_minimum_size = Vector2(0, 34)
	_play_col.add_child(_toast)
	board = BoardView.new()
	board.cell_pressed.connect(press_cell)
	_play_col.add_child(board)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	for t: String in TOOLS:
		var k := _key(0, t, "")
		k.name = "Tool_" + t
		k.pressed.connect(press_tool.bind(t))
		_tools[t] = k
		tools.add_child(k)
	_play_col.add_child(tools)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	_row2 = HBoxContainer.new()
	_row2.add_theme_constant_override("separation", 10)
	_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	for d in range(1, 10):
		var k := _key(d)
		k.name = "Digit%d" % d
		k.pressed.connect(press_digit.bind(d))
		_keys[d] = k
		if d <= 5:
			row1.add_child(k)
		else:
			k.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_row2.add_child(k)
	_play_col.add_child(row1)
	_play_col.add_child(_row2)
	var spacer_b := Control.new()
	spacer_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_col.add_child(spacer_b)


func start_game(lv: int, seed_value := -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	_begin(SudokuGame.from_pool(lv, seed_value))


func start_daily(day := -1) -> void:
	if day < 0:
		day = SudokuGame.today()
	var saved: Dictionary = Settings.saved_game
	if int(saved.get("daily_day", -1)) == day:
		continue_game()
		return
	_begin(SudokuGame.daily(day))


func continue_game() -> void:
	var g := SudokuGame.from_dict(Settings.saved_game)
	if g == null or g.won:
		Settings.clear_game()
		show_menu()
		return
	_begin(g)


func _begin(g: SudokuGame) -> void:
	game = g
	notes_mode = false
	board.game = g
	board.selected = -1
	board.mistake_check = Settings.mistake_check
	_menu.visible = false
	_overlay.visible = false
	_play.visible = true
	_title_label.text = _game_title(g.level, g.daily_day)
	for t: String in TOOLS:
		_tools[t].caption = tr(TOOL_KEYS[t])
	_toast.text = ""
	_shown_sec = -1
	_save_t = 0.0
	_layout()
	_refresh()
	_save_game()


func _refresh() -> void:
	if game == null:
		return
	for d in range(1, 10):
		var k: PadKey = _keys[d]
		k.remaining = game.remaining(d)
		k.notes_mode = notes_mode
	_tools["notes"].active = notes_mode
	_tools["check"].active = Settings.mistake_check
	_tools["hint"].badge = str(game.hints_used) if game.hints_used > 0 else ""
	_tools["hint"].queue_redraw()
	_stats_label.text = tr("STATS_LINE") % [game.hints_used, game.mistakes]
	_update_timer()
	board.queue_redraw()


func _update_timer() -> void:
	var s := int(game.elapsed)
	if s != _shown_sec:
		_shown_sec = s
		_timer_label.text = fmt_time(game.elapsed)


func toast(msg: String) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(2.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func press_cell(i: int) -> void:
	if game == null or game.won:
		return
	board.selected = i
	board.queue_redraw()


func press_digit(d: int) -> void:
	if game == null or game.won:
		return
	var i := board.selected
	if i < 0:
		toast(tr("TAP_CELL"))
		return
	var changed := false
	if game.is_locked(i):
		board.shake()
		return
	if notes_mode:
		changed = game.toggle_note(i, d)
	elif game.values[i] == d:
		changed = game.erase(i)
	else:
		changed = game.set_value(i, d)
		if changed:
			board.pop(i)
			if Settings.mistake_check and game.is_wrong(i):
				board.shake()
			else:
				_flash_units(i)
	if changed:
		_after_change()


func press_tool(t: String) -> void:
	if game == null or game.won:
		return
	match t:
		"undo":
			var c := game.undo()
			if c >= 0:
				board.selected = c
				_after_change()
		"erase":
			if board.selected >= 0 and game.erase(board.selected):
				_after_change()
		"notes":
			notes_mode = not notes_mode
			if notes_mode:
				toast(tr("NOTES_ON"))
			_refresh()
		"hint":
			var c := game.hint(board.selected)
			if c < 0:
				toast(tr("NO_HINT"))
				return
			board.selected = c
			board.pop(c)
			_flash_units(c)
			_after_change()
		"check":
			Settings.set_mistake_check(not Settings.mistake_check)
			board.mistake_check = Settings.mistake_check
			toast(tr("CHECK_ON") if Settings.mistake_check else tr("CHECK_OFF"))
			_refresh()


func _after_change() -> void:
	_refresh()
	if game.won:
		_on_win()
		return
	if game.is_full():
		toast(tr("FULL_WRONG"))
		board.shake()
	_save_game()


## Flashes each row / column / box through `i` that is now complete and correct.
func _flash_units(i: int) -> void:
	var cells := []
	for u in [SudokuGrid.row(i), 9 + SudokuGrid.col(i), 18 + SudokuGrid.box(i)]:
		var ok := true
		for c in SudokuGrid.UNITS[u]:
			if game.values[c] != game.solution[c]:
				ok = false
				break
		if ok:
			for c in SudokuGrid.UNITS[u]:
				if not cells.has(c):
					cells.append(c)
	if not cells.is_empty():
		board.flash(cells, 0.015)


func _on_win() -> void:
	var g := game
	var last := maxi(board.selected, 0)
	board.selected = -1
	var order := range(81)
	order.sort_custom(func(a: int, b: int) -> bool:
		return absi(a / 9 - last / 9) + absi(a % 9 - last % 9) < absi(b / 9 - last / 9) + absi(b % 9 - last % 9))
	board.flash(order, 0.008)
	var record := Settings.record_win(g.level, g.elapsed, g.daily_day)
	_refresh()
	await get_tree().create_timer(0.9).timeout
	if game == g:
		_show_win(record)


# --- win overlay --------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.02, 0.03, 0.06, 0.72)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := _box(PANEL, 28, ACCENT)
	sb.set_border_width_all(3)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 36
	sb.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	_win_box = VBoxContainer.new()
	_win_box.add_theme_constant_override("separation", 16)
	panel.add_child(_win_box)
	_overlay.visible = false


func _show_win(record: bool) -> void:
	for c in _win_box.get_children():
		_win_box.remove_child(c)
		c.queue_free()
	var lv := game.level
	_win_box.add_child(_label(tr("SOLVED"), 64, ACCENT))
	_win_box.add_child(_label(_game_title(lv, game.daily_day), 28, MUTED))
	_win_box.add_child(_label(fmt_time(game.elapsed), 76, TEXT))
	var rec_text: String = tr("NEW_BEST") if record else tr("BEST") % fmt_time(Settings.best_times[lv])
	_win_box.add_child(_label(rec_text, 30, ACCENT if record else MUTED))
	_win_box.add_child(_label(tr("STATS_LINE") % [game.hints_used, game.mistakes], 24, MUTED))
	if game.daily_day >= 0:
		_win_box.add_child(_label(tr("STREAK_LINE") % Settings.streak, 28, TEXT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_win_box.add_child(gap)
	var next := Button.new()
	next.name = "Next"
	next.text = tr("NEXT")
	_style(next, true, 32)
	next.custom_minimum_size = Vector2(0, 100)
	next.pressed.connect(func() -> void:
		if _win_armed():
			start_game(lv))
	_win_box.add_child(next)
	var menu := Button.new()
	menu.name = "Menu"
	menu.text = tr("MENU")
	_style(menu, false, 30)
	menu.custom_minimum_size = Vector2(0, 92)
	menu.pressed.connect(func() -> void:
		if _win_armed():
			show_menu())
	_win_box.add_child(menu)
	_win_armed_at = Time.get_ticks_msec() + 700
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	var panel: Control = _win_box.get_parent()
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween().set_parallel()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _win_armed() -> bool:
	return Time.get_ticks_msec() >= _win_armed_at


func is_win_shown() -> bool:
	return _overlay.visible


# --- timer + persistence ---------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or game.won or not _play.visible:
		return
	game.tick(delta)
	_update_timer()
	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_game()


func _save_game() -> void:
	_save_t = 0.0
	if game != null and not game.won:
		Settings.store_game(game.to_dict())


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_save_game()
