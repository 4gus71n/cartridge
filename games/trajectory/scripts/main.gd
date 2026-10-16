extends Control
## Trajectory: menu, level select, game screen (plot + steppers / keypad),
## teaching blurbs and result sheet — all built in code so the look lives in
## one place (_build_theme). Game rules live in plain classes (MathExpr,
## Flight, Levels, Forms, Progress, KeyBuffer) that the tests cover.

const BG := Color("#0b0e18")
const PANEL := Color("#171e33")
const PANEL_HI := Color("#222b47")
const ACCENT := Color("#4cc9f0")
const GOLD := Color("#ffd166")
const TEXT := Color("#e6e9f2")
const MUTED := Color("#8a93ad")
const FAINT := Color("#5b6480")
const DANGER := Color("#ff6b81")
const GOOD := Color("#69db7c")
const PARAM_COLORS := ["#ffa94d", "#4cc9f0", "#b197fc", "#69db7c"]

const KEY_ROWS := [
	["7", "8", "9", "(", ")", "back"],
	["4", "5", "6", "*", "/", "^"],
	["1", "2", "3", "+", "-", "x"],
	["0", ".", "sq", "clear", "LAUNCH"],
]
const TRIG_ROW := ["sin", "cos", "pi"]
const KEY_LABELS := {"*": "×", "/": "÷", "-": "−", "sq": "x²", "clear": "C", "pi": "π"}

var level_index := -1
var level: Dictionary = {}
var params: Array = []
var values := {}
var buffer := KeyBuffer.new()
var tries := 0
var won := false

var _screen: Control
var _overlay: Control
var _plot: PlotView
var _eq: RichTextLabel
var _status: Label
var _tries_label: Label
var _launch: Button
var _value_labels := {}
var _busy_controls: Array = []
var _repeat_timer: Timer
var _repeat := []
var _cursor_on := true
var _cursor_timer: Timer
var _result_stars: StarsView
var _grow: Array = []
var _cell_buttons: Array = []
var _flex: Control
var _flex_top: Control
var _eq_boost := 0   ## control rows that soak up spare height on tall phones


func _ready() -> void:
	theme = _build_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_repeat_timer = Timer.new()
	_repeat_timer.one_shot = true
	_repeat_timer.timeout.connect(_on_repeat)
	add_child(_repeat_timer)
	_cursor_timer = Timer.new()
	_cursor_timer.wait_time = 0.55
	_cursor_timer.timeout.connect(func() -> void:
		_cursor_on = not _cursor_on
		if is_instance_valid(_eq) and level.get("form", "") == "free":
			_refresh_equation())
	add_child(_cursor_timer)
	_cursor_timer.start()
	var poster := _poster_level()
	if poster >= 0:
		_stage_poster(poster)
		return
	var q := _query()
	if q.contains("nointro"):
		for k in Levels.count():
			Settings.progress.seen[Levels.get_level(k).get("intro", "")] = true
	if q.contains("level="):
		# QA shortcut for screenshot scripts: ?level=N opens level N directly.
		_open_level(clampi(int(q.get_slice("level=", 1).get_slice("&", 0)) - 1, 0, Levels.count() - 1))
		return
	if q.contains("screen=levels"):
		_show_levels()
		return
	_show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_draft()


# --- menu ---------------------------------------------------------------

func _show_menu() -> void:
	_save_draft()
	_clear()
	level_index = -1
	var m := _margin()
	_screen = m
	add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	m.add_child(box)
	box.add_child(_label(tr("TITLE"), 74, TEXT))
	var sub := _label(tr("SUBTITLE"), 27, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)

	var aspect := AspectRatioContainer.new()
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(aspect)
	var demo := PlotView.new()
	aspect.add_child(demo)
	var demo_level: Dictionary = Levels.get_level(Levels.count() - 1)
	demo.set_level(demo_level)
	demo.demo_expr = MathExpr.parse(Levels.ideal_expr(demo_level))

	var p := Settings.progress
	var next := p.next_level(Levels.count())
	var play := _primary_button(tr("PLAY") if p.total_stars() == 0 else tr("CONTINUE") % (next + 1), 112)
	play.pressed.connect(func() -> void: _open_level(next))
	box.add_child(play)
	var levels := _button(tr("LEVELS"), 96)
	levels.pressed.connect(_show_levels)
	box.add_child(levels)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(_single_star())
	row.add_child(_label(tr("STARS_TOTAL") % [p.total_stars(), Levels.count() * 3], 26, MUTED))
	var lang := Button.new()
	lang.text = tr("LANGUAGE")
	lang.flat = true
	lang.custom_minimum_size = Vector2(0, 88)
	lang.add_theme_color_override("font_color", ACCENT)
	lang.add_theme_color_override("font_hover_color", ACCENT)
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		_show_menu())
	box.add_child(lang)


func _single_star() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(30, 36)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		c.draw_colored_polygon(PlotView.star_points(c.size / 2.0, 14, 6.3), GOLD))
	return c


# --- level select ---------------------------------------------------------

func _show_levels() -> void:
	_save_draft()
	_clear()
	var m := _margin()
	_screen = m
	add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	m.add_child(box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	box.add_child(bar)
	var back := IconButton.new("back")
	back.pressed.connect(_show_menu)
	bar.add_child(back)
	var title := _label(tr("LEVELS"), 40, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	bar.add_child(_single_star())
	var total := _label("%d / %d" % [Settings.progress.total_stars(), Levels.count() * 3], 28, GOLD)
	total.custom_minimum_size = Vector2(88, 0)
	bar.add_child(total)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var next := Settings.progress.next_level(Levels.count())
	var focus: Control = null
	for w in Levels.WORLDS.size():
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		list.add_child(head)
		var name_l := _label(tr("WORLD_N") % (w + 1) + " · " + tr(Levels.WORLDS[w].key), 30, TEXT)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(name_l)
		var sub := _label(tr(Levels.WORLDS[w].key + "_SUB"), 23, MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(sub)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		list.add_child(grid)
		var start := Levels.world_start(w)
		for i in range(start, start + Levels.WORLDS[w].count):
			grid.add_child(_level_button(i, i == next))
		if Levels.world_of(next) == w and w > 0:
			focus = head
		list.add_child(_spacer(10))
	if focus != null:
		_scroll_to.call_deferred(scroll, focus)


func _scroll_to(scroll: ScrollContainer, c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(c):
		scroll.scroll_vertical = int(c.position.y)


func _level_button(i: int, is_next: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 124)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var open := Settings.progress.unlocked(i)
	var best := Settings.progress.best(i)
	b.disabled = not open
	b.draw.connect(func() -> void:
		var font := b.get_theme_default_font()
		var s := b.size
		if is_next and open:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = ACCENT
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(22)
			b.draw_style_box(sb, Rect2(Vector2.ZERO, s))
		if open:
			var t := str(i + 1)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
			b.draw_string(font, Vector2((s.x - tw) / 2.0, s.y * 0.52), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, TEXT)
			for k in 3:
				var c := Vector2(s.x / 2.0 + (k - 1) * 25.0, s.y * 0.76)
				b.draw_colored_polygon(PlotView.star_points(c, 10, 4.5), GOLD if k < best else Color(1, 1, 1, 0.13))
		else:
			var c := s / 2.0
			b.draw_arc(c + Vector2(0, -6), 11, PI, TAU, 16, FAINT, 4.0, true)
			b.draw_rect(Rect2(c + Vector2(-15, -6), Vector2(30, 24)), FAINT))
	b.pressed.connect(_open_level.bind(i))
	return b


# --- game screen ----------------------------------------------------------

func _open_level(i: int) -> void:
	_save_draft()
	level_index = i
	level = Levels.get_level(i)
	won = false
	Settings.progress.last_level = i
	params = Forms.params_for(level) if level.form != "free" else []
	values = Forms.initial_values(level)
	buffer = KeyBuffer.new()
	var d := Settings.progress.draft(i)
	tries = int(d.get("tries", 0))
	var input := str(d.get("input", ""))
	if input != "":
		if level.form == "free":
			buffer.set_text(input)
		else:
			var parsed = JSON.parse_string(input)
			if parsed is Dictionary:
				for p in params:
					if not p.locked and parsed.has(p.name):
						var v := clampf(float(parsed[p.name]), p.min, p.max)
						values[p.name] = p.min + roundf((v - p.min) / p.step) * p.step
	_build_game()
	_refresh()
	_set_status(_hint(), MUTED)
	var key: String = level.get("intro", "")
	if key != "" and not Settings.progress.seen.has(key):
		_show_intro(key)


func _hint() -> String:
	if not level.preview:
		return tr("HINT_HIDDEN")
	return tr("HINT_KEYPAD") if level.form == "free" else tr("HINT_STEPPER")


func _build_game() -> void:
	_clear()
	_busy_controls.clear()
	_value_labels.clear()
	var m := _margin(28, 22)
	_screen = m
	add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	m.add_child(box)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	box.add_child(bar)
	var back := IconButton.new("back")
	back.pressed.connect(_show_levels)
	bar.add_child(back)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	bar.add_child(titles)
	var t1 := _label(tr("LEVEL_N") % (level_index + 1), 32, TEXT)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(t1)
	var t2 := _label(tr(Levels.WORLDS[Levels.world_of(level_index)].key), 22, MUTED)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(t2)
	_tries_label = _label("", 24, MUTED)
	_tries_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_tries_label)
	var info := IconButton.new("info")
	info.icon_color = ACCENT
	info.pressed.connect(func() -> void: _show_intro(_intro_for(level_index)))
	bar.add_child(info)

	var aspect := AspectRatioContainer.new()
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(aspect)
	_plot = PlotView.new()
	aspect.add_child(_plot)
	_plot.set_level(level)
	_plot.flight_finished.connect(_on_flight_finished)
	_plot.target_hit.connect(func(_t: int) -> void: Input.vibrate_handheld(15))

	_flex_top = Control.new()
	_flex_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_flex_top)
	_eq = RichTextLabel.new()
	_eq.bbcode_enabled = true
	_eq.fit_content = true
	_eq.scroll_active = false
	_eq.autowrap_mode = TextServer.AUTOWRAP_OFF
	_eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eq.custom_minimum_size = Vector2(0, 54)
	_eq.add_theme_color_override("default_color", TEXT)
	box.add_child(_eq)
	_status = _label("", 25, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)
	box.add_child(_status)

	_flex = Control.new()
	_flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_flex)
	_grow.clear()
	_eq_boost = 0
	if level.form == "free":
		_build_keypad(box)
	else:
		_build_steppers(box)
	_fit_controls()


## Tall phones (9:20+) leave spare height around the square plot: give some
## of it to the control rows (bigger buttons), then pin the plot + equation
## to the top and push the controls down to the thumbs.
func _fit_controls() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_plot) or _grow.is_empty():
		return
	var aspect := _plot.get_parent() as Control
	var gap := aspect.size.y - aspect.size.x
	if gap <= 8.0:
		return
	var per := minf(gap * 0.5 / _grow.size(), 30.0)
	for row in _grow:
		for c in row:
			if is_instance_valid(c):
				(c as Control).custom_minimum_size.y += per
	aspect.size_flags_vertical = Control.SIZE_FILL
	aspect.custom_minimum_size.y = aspect.size.x
	_flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flex_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flex_top.size_flags_stretch_ratio = 0.5
	if gap - per * _grow.size() > 160.0:
		_eq_boost = 8
		_refresh_equation()


func _build_steppers(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 1 if params.size() == 1 else 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for k in params.size():
		grid.add_child(_stepper_cell(k))
		if k % 2 == 0:
			_grow.append([])
		_grow[_grow.size() - 1].append_array(_cell_buttons)
	_launch = _primary_button(tr("LAUNCH"), 100)
	_grow.append([_launch])
	_launch.pressed.connect(launch)
	_busy_controls.append(_launch)
	box.add_child(_launch)


func _stepper_cell(k: int) -> Control:
	var p: Dictionary = params[k]
	var col := Color(PARAM_COLORS[k])
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := _box(PANEL, 20)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	panel.add_child(h)
	var minus := _step_button("−")
	h.add_child(minus)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", -4)
	h.add_child(mid)
	var name_l := _label(p.name + ("  · " + tr("FIXED") if p.locked else ""), 22, Color(col, 0.85))
	mid.add_child(name_l)
	var val := _label("", 38, col)
	mid.add_child(val)
	_value_labels[p.name] = val
	var plus := _step_button("+")
	h.add_child(plus)
	_cell_buttons = [minus, plus]
	if p.locked:
		minus.disabled = true
		plus.disabled = true
		panel.modulate = Color(1, 1, 1, 0.6)
	else:
		for pair in [[minus, -1], [plus, 1]]:
			var b: Button = pair[0]
			b.button_down.connect(_hold_start.bind(p.name, pair[1]))
			b.button_up.connect(_hold_stop)
			_busy_controls.append(b)
	return panel


func _step_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 88)
	b.add_theme_font_size_override("font_size", 44)
	var sb := _box(PANEL_HI, 16)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	return b


func _hold_start(pname: String, dir: int) -> void:
	nudge(pname, dir)
	_repeat = [pname, dir]
	_repeat_timer.start(0.42)


func _hold_stop() -> void:
	_repeat_timer.stop()
	_repeat = []


func _on_repeat() -> void:
	if _repeat.is_empty() or _plot == null or _plot.is_flying():
		return
	nudge(_repeat[0], _repeat[1])
	_repeat_timer.start(0.085)


## Steps one parameter by `dir` steps (clamped to its range).
func nudge(pname: String, dir: int) -> void:
	if won or (_plot != null and _plot.is_flying()):
		return
	for p in params:
		if p.name != pname or p.locked:
			continue
		var v := clampf(float(values[pname]) + dir * p.step, p.min, p.max)
		v = p.min + roundf((v - p.min) / p.step) * p.step
		if absf(v) < 1e-9:
			v = 0.0
		if is_equal_approx(v, values[pname]):
			return
		values[pname] = v
		_refresh()
		_set_status(_hint(), MUTED)
		var l: Label = _value_labels[pname]
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2(1.12, 1.12)
		create_tween().tween_property(l, "scale", Vector2.ONE, 0.12)


func _build_keypad(box: VBoxContainer) -> void:
	var pad := VBoxContainer.new()
	pad.add_theme_constant_override("separation", 8)
	box.add_child(pad)
	var rows: Array = KEY_ROWS.duplicate()
	if level.get("keys", "") == "trig":
		rows.insert(0, TRIG_ROW)
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		pad.add_child(row)
		var grow_row := []
		_grow.append(grow_row)
		for key in r:
			var b: Button
			if key == "LAUNCH":
				b = _primary_button(tr("LAUNCH"), 82)
				b.size_flags_stretch_ratio = 2.08
				b.pressed.connect(launch)
				_launch = b
			elif key == "back":
				b = IconButton.new("backspace")
				b.pressed.connect(press_key.bind(key))
			else:
				b = Button.new()
				b.text = KEY_LABELS.get(key, key)
				b.focus_mode = Control.FOCUS_NONE
				b.add_theme_font_size_override("font_size", 34 if key.length() == 1 or key == "sq" else 30)
				if key in ["*", "/", "+", "-", "^", "(", ")"]:
					b.add_theme_color_override("font_color", ACCENT)
				elif key in ["x", "sq", "sin", "cos", "pi"]:
					b.add_theme_color_override("font_color", GOLD)
				elif key == "clear":
					b.add_theme_color_override("font_color", DANGER)
				b.pressed.connect(press_key.bind(key))
			b.custom_minimum_size = Vector2(0, 82 if r != TRIG_ROW else 72)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
			grow_row.append(b)
			_busy_controls.append(b)


func press_key(key: String) -> void:
	if won or (_plot != null and _plot.is_flying()):
		return
	if buffer.press(key):
		_cursor_on = true
		_refresh()
		_set_status(_hint(), MUTED)


## The expression currently entered (steppers or keypad).
func current_expr() -> MathExpr:
	if level.form == "free":
		return buffer.parse()
	return MathExpr.parse(Forms.expr(level.form, values))


func _current_input() -> String:
	return buffer.text() if level.form == "free" else JSON.stringify(values)


func _current_pretty(colored: bool) -> String:
	if level.form == "free":
		return KeyBuffer.display(buffer.text() + ")".repeat(buffer.missing_parens()))
	var colors := {}
	if colored:
		for k in params.size():
			colors[params[k].name] = PARAM_COLORS[k]
	return Forms.pretty(level.form, values, colors)


func _refresh() -> void:
	_refresh_equation()
	for p in params:
		(_value_labels[p.name] as Label).text = Forms.num_signed(values[p.name])
	_tries_label.text = tr("TRIES") % tries
	if level.preview and not won:
		var e := current_expr()
		_plot.preview = e if e.ok else null
	_plot.queue_redraw()


func _refresh_equation() -> void:
	var body := ""
	var plain_len := 0
	if level.form == "free":
		var disp := KeyBuffer.display(buffer.text())
		plain_len = disp.length()
		if disp == "":
			body = "[color=%s]…[/color]" % FAINT.to_html(false)
		else:
			body = disp + "[color=%s]%s[/color]" % [FAINT.to_html(false), ")".repeat(buffer.missing_parens())]
		if not won and not (_plot != null and _plot.is_flying()):
			body += "[color=%s]|[/color]" % (ACCENT.to_html(false) if _cursor_on else "00000000")
	else:
		body = _current_pretty(true)
		plain_len = _current_pretty(false).length()
	var fs := 40 if plain_len <= 18 else (32 if plain_len <= 26 else 26)
	_eq.add_theme_font_size_override("normal_font_size", fs + _eq_boost)
	_eq.text = "[center]y = %s[/center]" % body


func _set_status(text: String, color: Color) -> void:
	if is_instance_valid(_status):
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _set_busy(on: bool) -> void:
	for b in _busy_controls:
		if is_instance_valid(b):
			b.disabled = on
	if on:
		_hold_stop()


## Launches the rocket along the current curve (no-op while flying).
func launch() -> void:
	if won or _plot == null or _plot.is_flying():
		return
	var e := current_expr()
	if not e.ok:
		_set_status(tr(e.error), DANGER)
		_shake(_eq)
		return
	tries += 1
	_refresh()
	_save_draft()
	_set_busy(true)
	_set_status(tr("FLYING"), MUTED)
	_plot.preview = null
	_plot.launch(Flight.simulate(e, level))
	Input.vibrate_handheld(20)


func _on_flight_finished(res: Dictionary) -> void:
	_set_busy(false)
	if res.success:
		won = true
		var s := Progress.stars_for_attempts(tries)
		Settings.progress.record(level_index, s)
		Settings.save()
		_plot.ideal = MathExpr.parse(Levels.ideal_expr(level))
		_plot.preview = null
		_refresh_equation()
		Input.vibrate_handheld(60)
		_show_result(s)
		return
	_plot.ghost = res.points
	_plot.clear_flight()
	var msg := ""
	match res.crash:
		Flight.Crash.ROCK:
			msg = tr("CRASH_ROCK")
		Flight.Crash.WALL:
			msg = tr("CRASH_WALL")
		Flight.Crash.UNDEFINED:
			msg = tr("CRASH_UNDEF") % Forms.num(snappedf(res.crash_point.x, 0.1))
		_:
			var missed := Flight.missed_count(res)
			msg = tr("MISSED_1") if missed == 1 else tr("MISSED_N") % missed
	_set_status(msg, DANGER)
	Input.vibrate_handheld(160 if res.crash != Flight.Crash.NONE else 40)
	_refresh()


func _save_draft() -> void:
	if level_index < 0 or won or level.is_empty():
		return
	var input := _current_input()
	var initial := "" if level.form == "free" else JSON.stringify(Forms.initial_values(level))
	if tries == 0 and input == initial:
		if Settings.progress.drafts.has(level_index):
			Settings.progress.drafts.erase(level_index)
			Settings.save()
		return
	Settings.progress.set_draft(level_index, input, tries)
	Settings.save()


## Latest teaching blurb at or before level i.
func _intro_for(i: int) -> String:
	for k in range(i, -1, -1):
		var key: String = Levels.get_level(k).get("intro", "")
		if key != "":
			return key
	return "CONST"


# --- overlays -------------------------------------------------------------

func _show_intro(key: String) -> void:
	_close_overlay()
	Settings.progress.seen[key] = true
	Settings.save()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	box.add_child(_label(tr("NEW_IDEA"), 24, GOLD))
	var title := _label(tr("INTRO_%s_T" % key), 36, ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var body := _label(tr("INTRO_%s" % key), 28, TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(body)
	var ok := _primary_button(tr("GOT_IT"), 96)
	ok.pressed.connect(_close_overlay)
	box.add_child(ok)
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(310, 200)
	panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_result(stars: int) -> void:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var m := _margin(0, 22)
	_overlay.add_child(m)
	var col := VBoxContainer.new()
	m.add_child(col)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(gap)
	var panel := PanelContainer.new()
	var psb := _box(PANEL, 28)
	psb.border_color = Color(GOOD, 0.5)
	psb.set_border_width_all(2)
	psb.content_margin_left = 28
	psb.content_margin_right = 28
	psb.content_margin_top = 24
	psb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", psb)
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label(tr("WON"), 52, GOOD))
	_result_stars = StarsView.new(stars, 30.0)
	_result_stars.custom_minimum_size = Vector2(0, 64)
	_result_stars.pops = [0.0, 0.0, 0.0]
	box.add_child(_result_stars)
	var tw := create_tween()
	for k in 3:
		tw.tween_method(_result_stars.set_pop.bind(k), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	box.add_child(_label(tr("FIRST_TRY") if tries <= 1 else tr("SOLVED_IN") % tries, 26, MUTED))
	box.add_child(_formula_line(tr("YOUR_CURVE"), "y = " + _current_pretty(false), TEXT))
	var ideal_text := "y = " + _ideal_display()
	box.add_child(_formula_line(tr("IDEAL"), ideal_text, GOLD))
	var co := Poly.fit(MathExpr.parse(Levels.ideal_expr(level)))
	if not co.is_empty():
		var expanded := "y = " + Poly.format(co)
		if expanded != ideal_text:
			box.add_child(_formula_line(tr("EXPANDED"), expanded, Color(GOLD, 0.75)))
	box.add_child(_spacer(6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var again := _button(tr("REPLAY"), 96)
	again.add_theme_stylebox_override("normal", _box(PANEL_HI))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void: _open_level(level_index))
	row.add_child(again)
	if level_index + 1 < Levels.count():
		var next := _primary_button(tr("NEXT"), 96)
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next.size_flags_stretch_ratio = 1.4
		next.pressed.connect(func() -> void: _open_level(level_index + 1))
		row.add_child(next)
	if Settings.progress.next_level(Levels.count()) == Levels.count() - 1 \
			and Settings.progress.solved(Levels.count() - 1):
		box.add_child(_label(tr("ALL_DONE"), 28, GOLD))
	var levels := _button(tr("LEVELS"), 88)
	levels.flat = true
	levels.add_theme_color_override("font_color", ACCENT)
	levels.pressed.connect(_show_levels)
	box.add_child(levels)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)


func _ideal_display() -> String:
	if level.form == "free":
		return KeyBuffer.display(level.ideal)
	return Levels.ideal_pretty(level)


func _formula_line(caption: String, formula: String, color: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.add_child(_label(caption, 21, MUTED))
	var f := _label(formula, 32 if formula.length() <= 26 else 26, color)
	f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(f)
	return v


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func has_overlay() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion()


# --- poster capture ---------------------------------------------------------

## ?poster=N[&x=X] in the page URL stages level N with the rocket frozen
## mid-flight at world x = X (used to capture poster.png from the web build).
func _poster_level() -> int:
	var q := _query()
	if not q.contains("poster="):
		return -1
	return clampi(int(q.get_slice("poster=", 1).get_slice("&", 0)) - 1, 0, Levels.count() - 1)


func _query() -> String:
	if not OS.has_feature("web"):
		return ""
	var q = JavaScriptBridge.eval("window.location.search", true)
	return str(q) if typeof(q) == TYPE_STRING else ""


func _stage_poster(i: int) -> void:
	for k in Levels.count():
		Settings.progress.seen[Levels.get_level(k).get("intro", "")] = true
	_open_level(i)
	if level.form == "free":
		buffer.set_text(level.ideal)
	else:
		for k in level.ideal:
			values[k] = float(level.ideal[k])
	tries = 0
	_refresh()
	await get_tree().process_frame
	launch()
	var q := _query()
	var x := float(q.get_slice("x=", 1).get_slice("&", 0)) if q.contains("x=") else 2.0
	await get_tree().create_timer((x - Flight.X_MIN) / PlotView.SPEED).timeout
	_plot.freeze_at(x)
	_set_busy(false)


# --- helpers ------------------------------------------------------------

func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := create_tween()
	for k in 4:
		tw.tween_property(c, "position:x", x + (12 if k % 2 == 0 else -12), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


func _clear() -> void:
	_close_overlay()
	_hold_stop()
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	_plot = null
	_eq = null
	_status = null


func _margin(top := 40, bottom := 32) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, h: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	return b


func _primary_button(text: String, h: int) -> Button:
	var b := _button(text, h)
	b.theme_type_variation = "PrimaryButton"
	return b


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var normal := _box(PANEL)
	var hover := normal  # touch-first: no sticky hover highlight after a tap
	var pressed := _box(ACCENT.darkened(0.45))
	var disabled := _box(PANEL.darkened(0.25))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(ACCENT))
	t.set_stylebox("hover", "PrimaryButton", _box(ACCENT))
	t.set_stylebox("pressed", "PrimaryButton", _box(ACCENT.darkened(0.2)))
	t.set_stylebox("hover_pressed", "PrimaryButton", _box(ACCENT.darkened(0.2)))
	t.set_stylebox("disabled", "PrimaryButton", _box(ACCENT.darkened(0.6)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color"]:
		t.set_color(c, "PrimaryButton", BG)
	t.set_color("font_disabled_color", "PrimaryButton", Color(BG, 0.6))
	t.set_font_size("font_size", "PrimaryButton", 34)
	var panel := _box(PANEL, 28)
	panel.content_margin_left = 36
	panel.content_margin_right = 36
	panel.content_margin_top = 32
	panel.content_margin_bottom = 28
	t.set_stylebox("panel", "PanelContainer", panel)
	var grab := _box(Color(1, 1, 1, 0.18), 4)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


func _box(color: Color, radius := 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb
