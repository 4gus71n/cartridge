extends Control
## Minefield: menu, game screen and result overlay, all built in code so the
## UI can be restyled later from one place (_build_theme).

const DIFFICULTIES := [
	{"id": "easy", "name": "EASY", "w": 9, "h": 9, "m": 10},
	{"id": "medium", "name": "MEDIUM", "w": 10, "h": 14, "m": 24},
	{"id": "hard", "name": "HARD", "w": 12, "h": 20, "m": 44},
]
const BG := Color("#0b0e18")
const PANEL := Color("#171e33")
const ACCENT := Color("#ff4d6d")
const TEXT := Color("#e6e9f2")
const MUTED := Color("#8a93ad")

var board: MineBoard
var difficulty: Dictionary = DIFFICULTIES[0]
var flag_mode := false
var elapsed := 0.0
var running := false
var generating := false
var rng := RandomNumberGenerator.new()

var _menu: Control
var _game: Control
var _overlay: Control
var _view: BoardView
var _mines_label: Label
var _time_label: Label
var _status_label: Label
var _mode_button: Button


func _ready() -> void:
	rng.randomize()
	theme = _build_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_show_menu()


func _process(delta: float) -> void:
	if running:
		elapsed += delta
		_time_label.text = Settings.format_time(elapsed)


# --- menu ---------------------------------------------------------------

func _show_menu() -> void:
	_clear_screens()
	_menu = _margin()
	add_child(_menu)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	_menu.add_child(box)

	var title := _label(tr("TITLE"), 76, TEXT)
	box.add_child(title)
	var sub := _label(tr("SUBTITLE"), 26, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(_spacer(30))

	for d in DIFFICULTIES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 132)
		var best = Settings.best_times.get(d.id)
		var best_text: String = tr("NO_BEST") if best == null else tr("BEST") % Settings.format_time(best)
		button.text = "%s\n%s · %s" % [tr(d.name), tr("BOARD_INFO") % [d.w, d.h, d.m], best_text]
		button.pressed.connect(_start.bind(d))
		box.add_child(button)

	box.add_child(_spacer(20))
	var how := _label(tr("HOW_TO"), 24, MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(how)

	var lang := Button.new()
	lang.text = tr("LANGUAGE")
	lang.flat = true
	lang.add_theme_color_override("font_color", ACCENT)
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		_show_menu())
	box.add_child(lang)


# --- game ---------------------------------------------------------------

func _start(d: Dictionary) -> void:
	difficulty = d
	board = MineBoard.new(d.w, d.h, d.m)
	elapsed = 0.0
	running = false
	flag_mode = false
	_clear_screens()
	_game = _margin()
	add_child(_game)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_game.add_child(box)

	var hud := HBoxContainer.new()
	box.add_child(hud)
	_mines_label = _label("", 34, TEXT)
	_mines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_mines_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(_mines_label)
	var diff_label := _label(tr(d.name), 28, MUTED)
	diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(diff_label)
	_time_label = _label("0:00", 34, TEXT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(_time_label)

	_status_label = _label(tr("FIRST_TAP"), 24, MUTED)
	box.add_child(_status_label)

	_view = BoardView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.cell_tapped.connect(_on_tap)
	_view.cell_long_pressed.connect(_on_long_press)
	box.add_child(_view)
	_view.set_board(board)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	box.add_child(bar)
	var menu := _bar_button(tr("MENU"))
	menu.pressed.connect(_show_menu)
	bar.add_child(menu)
	_mode_button = _bar_button(tr("MODE_DIG"))
	_mode_button.toggle_mode = true
	_mode_button.toggled.connect(func(on: bool) -> void:
		flag_mode = on
		_mode_button.text = tr("MODE_FLAG") if on else tr("MODE_DIG"))
	bar.add_child(_mode_button)
	var restart := _bar_button(tr("RESTART"))
	restart.pressed.connect(func() -> void: _start(difficulty))
	bar.add_child(restart)
	_update_hud()


func _on_tap(cell: int) -> void:
	if generating:
		return
	if board.state == MineBoard.State.READY:
		await _first_reveal(cell)
		return
	if board.state != MineBoard.State.PLAYING:
		return
	if board.revealed[cell]:
		_view.animate_reveal(board.chord(cell))
	elif flag_mode:
		_flag(cell)
		return
	else:
		_view.animate_reveal(board.reveal(cell))
	_after_move()


func _on_long_press(cell: int) -> void:
	if generating or board.state != MineBoard.State.PLAYING:
		return
	if board.revealed[cell]:
		_view.animate_reveal(board.chord(cell))
		_after_move()
	else:
		_flag(cell)


func _flag(cell: int) -> void:
	if board.toggle_flag(cell):
		Input.vibrate_handheld(25)
		_update_hud()
		_view.queue_redraw()


## First tap: build a no-guess board around it. Work is split across frames
## so the page stays responsive on slow phones (web builds have no threads).
func _first_reveal(cell: int) -> void:
	generating = true
	_status_label.text = tr("GENERATING")
	# Let the "generating" label paint before the CPU-heavy search starts.
	await get_tree().process_frame
	var found := false
	var attempts := 0
	# Time-budgeted: ~12 ms of attempts per frame keeps slow WebViews responsive.
	while attempts < 750 and not found:
		var frame_start := Time.get_ticks_msec()
		while attempts < 750 and Time.get_ticks_msec() - frame_start < 12:
			attempts += 1
			if board.generate(cell, rng, true, 1):
				found = true
				break
		if not found:
			await get_tree().process_frame
	if not found:
		push_warning("no-guess board not found; using last layout")
	generating = false
	_status_label.text = ""
	running = true
	_view.animate_reveal(board.reveal(cell))
	_after_move()


func _after_move() -> void:
	_update_hud()
	if board.state == MineBoard.State.WON or board.state == MineBoard.State.LOST:
		running = false
		Input.vibrate_handheld(60 if board.state == MineBoard.State.WON else 200)
		_view.queue_redraw()
		get_tree().create_timer(0.6 if board.state == MineBoard.State.LOST else 0.4) \
			.timeout.connect(_show_result)


func _update_hud() -> void:
	_mines_label.text = tr("MINES_LEFT") % board.mines_left()


func _show_result() -> void:
	if _overlay:
		_overlay.queue_free()
	var won := board.state == MineBoard.State.WON
	var record := won and Settings.submit_time(difficulty.id, elapsed)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_label(tr("WON") if won else tr("LOST"), 64, TEXT if won else ACCENT))
	if won:
		box.add_child(_label(tr("TIME") % Settings.format_time(elapsed), 32, TEXT))
		if record:
			box.add_child(_label(tr("NEW_BEST"), 30, Color("#ffd166")))
	var again := Button.new()
	again.text = tr("PLAY_AGAIN")
	again.custom_minimum_size = Vector2(0, 96)
	again.pressed.connect(func() -> void: _start(difficulty))
	box.add_child(again)
	var menu := Button.new()
	menu.text = tr("MENU")
	menu.flat = true
	menu.pressed.connect(_show_menu)
	box.add_child(menu)


# --- helpers ------------------------------------------------------------

func _clear_screens() -> void:
	for node in [_menu, _game, _overlay]:
		if is_instance_valid(node):
			node.queue_free()
	_menu = null
	_game = null
	_overlay = null


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 32)
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
	return c


func _bar_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 26)
	return b


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var normal := _box(PANEL)
	var hover := _box(PANEL.lightened(0.08))
	var pressed := _box(ACCENT.darkened(0.25))
	for type in ["Button"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, TEXT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, TEXT)
	var panel := _box(PANEL)
	panel.content_margin_left = 36
	panel.content_margin_right = 36
	panel.content_margin_top = 36
	panel.content_margin_bottom = 28
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


func _box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	return sb
