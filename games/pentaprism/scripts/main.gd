extends Control
## Pentaprism: menu, game screen, pause + game-over overlays, built in code
## so the UI can be restyled from one place (_build_theme).

const BG := Color("#0d0b1e")
const BG_BOTTOM := Color("#1d1240")
const PANEL := Color("#1b1838")
const ACCENT := Color("#8f6bff")
const TEXT := Color("#ece9ff")
const MUTED := Color("#8a86b0")
const GOLD := Color("#ffd166")

var board: PrismBoard
var view: BoardView
var paused := false
var _game_id := 0
var _resolving := false
var _shown_score := 0.0
var _last_level := 1

var _menu: Control
var _game: Control
var _overlay: Control
var _score_label: Label
var _level_label: Label
var _best_label: Label
var _status_label: Label
var _hold_view: PiecePreview
var _next_view: PiecePreview


func _ready() -> void:
	theme = _build_theme()
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, BG)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _game != null and board != null and board.state != PrismBoard.State.OVER and not paused:
			_pause()


# --- menu ---------------------------------------------------------------

func _show_menu() -> void:
	_clear_screens()
	_game_id += 1
	board = null
	_menu = _margin()
	add_child(_menu)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	_menu.add_child(box)

	var art := MenuArt.new()
	art.custom_minimum_size = Vector2(0, 250)
	box.add_child(art)
	box.add_child(_label(tr("TITLE"), 80, TEXT))
	var sub := _label(tr("SUBTITLE"), 28, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(_spacer(16))

	var play := Button.new()
	play.text = tr("PLAY")
	play.custom_minimum_size = Vector2(0, 128)
	play.add_theme_font_size_override("font_size", 44)
	play.add_theme_stylebox_override("normal", _box(ACCENT))
	play.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1)))
	play.pressed.connect(start_game)
	box.add_child(play)

	var best := _label(tr("BEST_LINE") % [Settings.best_score, Settings.best_chain], 28, GOLD)
	box.add_child(best)
	box.add_child(_spacer(6))
	var rules := _label(tr("RULES"), 25, TEXT)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rules)
	var how := _label(tr("HOW_TO"), 24, MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(how)

	var lang := Button.new()
	lang.text = tr("LANGUAGE")
	lang.flat = true
	lang.custom_minimum_size = Vector2(0, 88)
	lang.add_theme_color_override("font_color", ACCENT.lightened(0.3))
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		_show_menu())
	box.add_child(lang)


# --- game ---------------------------------------------------------------

func start_game(seed_value: int = -1) -> void:
	_clear_screens()
	_game_id += 1
	paused = false
	_resolving = false
	board = PrismBoard.new(9, 16, seed_value)
	_shown_score = 0.0
	_last_level = 1

	_game = _margin()
	_game.add_theme_constant_override("margin_top", 28)
	_game.add_theme_constant_override("margin_bottom", 16)
	add_child(_game)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_game.add_child(box)

	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 14)
	box.add_child(hud)
	var pause := Button.new()
	pause.text = "II"
	pause.custom_minimum_size = Vector2(88, 88)
	pause.add_theme_font_size_override("font_size", 32)
	pause.pressed.connect(_pause)
	hud.add_child(pause)
	_score_label = _stat(hud, tr("SCORE"), 48, true)
	_level_label = _stat(hud, tr("LEVEL"), 36, false)
	_level_label.get_parent().custom_minimum_size = Vector2(120, 0)
	_best_label = _stat(hud, tr("BEST"), 36, false)
	_best_label.get_parent().custom_minimum_size = Vector2(150, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 128)
	box.add_child(row)
	_hold_view = PiecePreview.new()
	_hold_view.title = tr("HOLD")
	_hold_view.custom_minimum_size = Vector2(150, 128)
	_hold_view.pressed.connect(func() -> void: _do("hold"))
	row.add_child(_hold_view)
	_status_label = _label("", 28, GOLD)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_status_label)
	_next_view = PiecePreview.new()
	_next_view.title = tr("NEXT")
	_next_view.custom_minimum_size = Vector2(300, 128)
	_next_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_next_view)

	view = BoardView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.action.connect(_do)
	box.add_child(view)
	view.set_board(board)

	var hint := _label(tr("HINT"), 22, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	board.start()
	_update_hud()


func _process(delta: float) -> void:
	if board == null or _game == null or paused:
		return
	if board.state == PrismBoard.State.PLAYING:
		var piece := board.current
		if board.update(delta):
			_after_lock(piece)
	_update_hud(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or board == null or _game == null:
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_LEFT, KEY_A:
			_do("left")
		KEY_RIGHT, KEY_D:
			_do("right")
		KEY_UP, KEY_X, KEY_W:
			_do("rotate")
		KEY_Z:
			_do("rotate_ccw")
		KEY_DOWN, KEY_S:
			_do("soft")
		KEY_SPACE:
			_do("hard")
		KEY_C, KEY_SHIFT:
			_do("hold")
		KEY_ESCAPE, KEY_P:
			if paused:
				_resume()
			elif board.state != PrismBoard.State.OVER:
				_pause()
		_:
			return
	get_viewport().set_input_as_handled()


func _do(what: String) -> void:
	if board == null or paused or board.state != PrismBoard.State.PLAYING:
		return
	match what:
		"left":
			board.move(-1)
		"right":
			board.move(1)
		"rotate":
			board.rotate(1)
		"rotate_ccw":
			board.rotate(-1)
		"soft":
			board.soft_drop()
		"hard":
			var piece := board.current
			var from_y := piece.pos.y
			board.hard_drop()
			Input.vibrate_handheld(15)
			view.animate_hard_drop(piece, from_y)
			_after_lock(piece)
		"hold":
			if board.hold():
				Input.vibrate_handheld(10)
			if board.state == PrismBoard.State.OVER:
				_game_over()
	_update_hud()


## Animates settle → clear → settle … one step at a time, then spawns next.
func _after_lock(piece: Pieces.Piece) -> void:
	var gid := _game_id
	var locked := []
	for c in piece.cells:
		var x := piece.pos.x + c.x
		var y := piece.pos.y + c.y
		if y >= 0:
			locked.append(board.index(x, y))
	view.animate_lock(locked)
	if board.state == PrismBoard.State.OVER:
		_game_over()
		return
	_resolving = true
	while true:
		var step := board.resolve_step()
		if not step.falls.is_empty():
			view.animate_falls(step.falls)
			await _wait(BoardView.FALL_TIME + 0.02)
			if gid != _game_id:
				return
		if step.done:
			break
		view.animate_clear(step)
		Input.vibrate_handheld(30 + 10 * step.chain)
		if board.level > _last_level:
			_last_level = board.level
			view.popup(tr("LEVEL_UP") % board.level, view.size / 2.0, ACCENT.lightened(0.4), 56)
		await _wait(BoardView.CLEAR_TIME)
		if gid != _game_id:
			return
	_resolving = false
	var bonus := board.finish()
	if bonus > 0:
		_status_label.text = tr("COMBO") % board.combo
		_flash_label(_status_label)
	elif board.combo == 0:
		_status_label.text = ""
	if board.state == PrismBoard.State.OVER:
		_game_over()
	_update_hud()


func _wait(t: float) -> void:
	var left := t
	while left > 0.0:
		await get_tree().process_frame
		if not paused:
			left -= get_process_delta_time()


func _update_hud(delta := 0.0) -> void:
	if board == null or _score_label == null:
		return
	if delta > 0.0:
		_shown_score = move_toward(_shown_score, board.score, maxf(40.0, (board.score - _shown_score) * 8.0) * delta)
	else:
		_shown_score = board.score
	_score_label.text = str(int(_shown_score))
	_level_label.text = str(board.level)
	_best_label.text = str(maxi(Settings.best_score, board.score))
	_hold_view.show_pieces([board.held], not board.can_hold)
	_next_view.show_pieces(board.queue)


func _game_over() -> void:
	var gid := _game_id
	view.animate_game_over()
	Input.vibrate_handheld(200)
	var record := Settings.submit_game(board.score, board.best_chain)
	await _wait(1.2)
	if gid != _game_id:
		return
	_show_over(record)


# --- overlays -------------------------------------------------------------

func _pause() -> void:
	if board == null or board.state == PrismBoard.State.OVER or _overlay != null:
		return
	paused = true
	var box := _overlay_panel()
	box.add_child(_label(tr("PAUSED"), 60, TEXT))
	box.add_child(_label(tr("SCORE_LINE") % board.score, 30, MUTED))
	box.add_child(_big_button(tr("RESUME"), _resume))
	var restart := _flat(tr("RESTART"))
	restart.pressed.connect(func() -> void: start_game())
	box.add_child(restart)
	var menu := _flat(tr("MENU"))
	menu.pressed.connect(_show_menu)
	box.add_child(menu)


func _resume() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	paused = false


func _show_over(record: bool) -> void:
	var box := _overlay_panel()
	box.add_child(_label(tr("GAME_OVER"), 60, ACCENT.lightened(0.35)))
	var score := _label(str(board.score), 84, TEXT)
	box.add_child(score)
	if record:
		var nb := _label(tr("NEW_BEST"), 32, GOLD)
		box.add_child(nb)
		_flash_label(nb)
	else:
		box.add_child(_label(tr("BEST_SCORE") % Settings.best_score, 28, GOLD))
	var stats := _label(tr("STATS") % [board.level, board.best_chain, board.cleared_cells], 26, MUTED)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)
	box.add_child(_big_button(tr("PLAY_AGAIN"), func() -> void: start_game()))
	var menu := _flat(tr("MENU"))
	menu.pressed.connect(_show_menu)
	box.add_child(menu)


func _overlay_panel() -> VBoxContainer:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	panel.pivot_offset = Vector2(280, 200)
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	return box


# --- helpers ------------------------------------------------------------

func _clear_screens() -> void:
	for node in [_menu, _game, _overlay]:
		if is_instance_valid(node):
			node.queue_free()
	_menu = null
	_game = null
	_overlay = null
	_score_label = null


func _flash_label(l: Label) -> void:
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(1.25, 1.25)
	l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _stat(parent: Control, caption: String, font_size: int, expand: bool) -> Label:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	if expand:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	col.add_child(_label(caption, 20, MUTED))
	var value := _label("0", font_size, TEXT)
	col.add_child(value)
	return value


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


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 104)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_stylebox_override("normal", _box(ACCENT))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1)))
	b.pressed.connect(cb)
	return b


func _flat(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, 88)
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
	panel.border_color = Color(ACCENT, 0.5)
	panel.set_border_width_all(2)
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
