extends Control
## Mini Crossword: menu, puzzle list, play screen (grid + clue bar + custom
## keyboard), assist sheet, completion card and how-to. All UI is built in
## code. Public methods (open_puzzle, tap_cell, press_key, ...) are the same
## entry points the buttons use, so tests/ui_check.gd can drive the game.

const BG := Color("0b0e18")
const PANEL := Color("161b2b")
const PANEL_HI := Color("222a42")
const ACCENT := Color("ffb547")
const TEXT := Color("e8ebf5")
const MUTED := Color("8d94ab")
const GOOD := Color("5fd38d")
const SAVE_DELAY := 1.2

var pack: Array[Puzzle] = []
var lang := ""
var index := -1
var board: Board
var is_daily := false
var screen := "menu"

var _menu: Control
var _list: Control
var _game: Control
var _overlay: Control
var _grid: GridView
var _clue_dir: Label
var _clue_text: Label
var _title: Label
var _timer: Label
var _keyboard: VBoxContainer
var _toast: Label
var _toast_tween: Tween
var _dirty := false
var _since_save := 0.0
var _shown_second := -1
var _keys := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_load_pack()
	show_menu()


func _settings() -> Node:
	return get_node("/root/Settings")


func _load_pack() -> void:
	lang = _settings().language
	pack = Pack.load_pack(lang)


func daily_index() -> int:
	return Pack.daily_index(Pack.today(), pack.size())


# --- shared widgets --------------------------------------------------------

func _style(col: Color, radius := 22, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _skin(b: Button, col: Color, font_col := TEXT, radius := 22) -> void:
	b.add_theme_stylebox_override("normal", _style(col, radius))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.08), radius))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.15), radius))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", _style(col.darkened(0.4), radius))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, font_col)
	b.focus_mode = Control.FOCUS_NONE


func _button(text: String, primary := false, h := 104, fs := 32) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	_skin(b, ACCENT if primary else PANEL_HI, BG if primary else TEXT)
	return b


func _icon(kind: int, col := PANEL_HI) -> IconButton:
	var b := IconButton.new(kind)
	b.custom_minimum_size = Vector2(96, 96)
	_skin(b, col)
	return b


func _label(text: String, fs := 28, col := TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _screen_root() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 18)
	add_child(m)
	return m


func _clear_screens() -> void:
	for n in [_menu, _list, _game, _overlay]:
		if n and is_instance_valid(n):
			n.queue_free()
	_menu = null
	_list = null
	_game = null
	_overlay = null
	_grid = null


# --- menu ------------------------------------------------------------------

func show_menu() -> void:
	_leave_game()
	_clear_screens()
	screen = "menu"
	var root := _screen_root()
	_menu = root
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)
	v.add_child(_spacer(20))
	v.add_child(_label(tr("TITLE"), 60, ACCENT))
	var sub := _label(tr("SUBTITLE"), 28, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	# Logo: a sample puzzle, half filled.
	var logo := GridView.new()
	logo.show_cursor = false
	logo.custom_minimum_size = Vector2(0, 300)
	logo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not pack.is_empty():
		var demo := Board.new(pack[daily_index()])
		var k := 0
		for i in demo.puzzle.cell_count():
			if not demo.puzzle.is_block(i):
				if k % 3 != 2:
					demo.letters[i] = demo.puzzle.solution[i]
				k += 1
		logo.board = demo
	v.add_child(logo)
	var d := daily_index()
	var daily := _button(tr("DAILY") + "  ·  #%d" % (d + 1), true, 112, 34)
	daily.pressed.connect(open_puzzle.bind(d, true))
	v.add_child(daily)
	var cont := _continue_index()
	if cont >= 0 and cont != d:
		var c := _button(tr("CONTINUE") + "  ·  " + tr("PUZZLE_N") % (cont + 1))
		c.pressed.connect(open_puzzle.bind(cont, false))
		v.add_child(c)
	var all := _button(tr("ALL") + "  ·  " + tr("SOLVED_COUNT") % [solved_count(), pack.size()])
	all.pressed.connect(show_list)
	v.add_child(all)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var how := _button(tr("HOWTO"))
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.pressed.connect(show_howto)
	row.add_child(how)
	var lb := _button(tr("LANG"))
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.pressed.connect(toggle_language)
	row.add_child(lb)
	v.add_child(row)
	v.add_child(_spacer(10))


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _continue_index() -> int:
	var id: String = _settings().last.get(lang, "")
	if id == "" or not _settings().progress.has(id):
		return -1
	for i in pack.size():
		if pack[i].id == id:
			return i
	return -1


func solved_count() -> int:
	var n := 0
	for p in pack:
		if _settings().is_solved(p.id):
			n += 1
	return n


func toggle_language() -> void:
	_settings().set_language("es" if lang == "en" else "en")
	_load_pack()
	show_menu()


# --- puzzle list -------------------------------------------------------------

func show_list() -> void:
	_leave_game()
	_clear_screens()
	screen = "list"
	var root := _screen_root()
	_list = root
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)
	var top := HBoxContainer.new()
	var back := _icon(IconButton.Kind.BACK)
	back.pressed.connect(show_menu)
	top.add_child(back)
	var t := _label(tr("ALL"), 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(_label(tr("SOLVED_COUNT") % [solved_count(), pack.size()], 22, MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var g := GridContainer.new()
	g.columns = 4
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	scroll.add_child(g)
	var d := daily_index()
	for i in pack.size():
		g.add_child(_tile(i, i == d))


func _tile(i: int, daily: bool) -> Button:
	var p := pack[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var solved: bool = _settings().is_solved(p.id)
	var started: bool = _settings().progress.has(p.id)
	_skin(b, Color("1d3a2c") if solved else PANEL, TEXT, 20)
	if daily:
		b.add_theme_stylebox_override("normal", _style(Color("1d3a2c") if solved else PANEL, 20, ACCENT))
	b.pressed.connect(open_puzzle.bind(i, daily))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var num := _label(str(i + 1), 40, ACCENT if daily else TEXT)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(num)
	var info := tr("SIZE") % [p.width, p.height]
	var col := MUTED
	if solved:
		var bt: float = _settings().best_time(p.id)
		info = Pack.format_time(bt) if bt >= 0 else "—"
		col = GOOD
		var ck := IconButton.new(IconButton.Kind.CHECK)
		ck.flat = true
		ck.glyph_color = GOOD
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ck.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		ck.offset_left = -50
		ck.offset_bottom = 50
		b.add_child(ck)
	elif started:
		info = "• " + tr("IN_PROGRESS")
		col = ACCENT
	var l := _label(info, 22 if not started or solved else 18, col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	if daily:
		var tag := _label(tr("DAILY_TAG"), 18, ACCENT)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
	b.set_meta("solved", solved)
	return b


# --- play screen -------------------------------------------------------------

func open_puzzle(i: int, daily := false) -> void:
	_leave_game()
	_clear_screens()
	index = i
	is_daily = daily or i == daily_index()
	var p := pack[i]
	var saved: Dictionary = _settings().progress.get(p.id, {})
	board = Board.from_dict(p, saved) if not saved.is_empty() else Board.new(p)
	_settings().last[lang] = p.id
	screen = "game"
	_build_game()
	refresh()


func _build_game() -> void:
	var root := _screen_root()
	_game = root
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)
	# top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var back := _icon(IconButton.Kind.BACK)
	back.pressed.connect(show_list)
	top.add_child(back)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	_title = _label("", 30)
	mid.add_child(_title)
	_timer = _label("0:00", 26, MUTED)
	mid.add_child(_timer)
	top.add_child(mid)
	var help := _icon(IconButton.Kind.HELP)
	help.pressed.connect(show_assist)
	top.add_child(help)
	v.add_child(top)
	# grid
	_grid = GridView.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size = Vector2(0, 360)
	_grid.cell_tapped.connect(tap_cell)
	v.add_child(_grid)
	_toast = _label("", 26, BG)
	_toast.add_theme_stylebox_override("normal", _style(ACCENT, 26))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_grid.add_child(_toast)
	# clue bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	var prev := _icon(IconButton.Kind.PREV, PANEL)
	prev.custom_minimum_size = Vector2(88, 124)
	prev.pressed.connect(prev_clue)
	bar.add_child(prev)
	var clue := Button.new()
	_skin(clue, Color("2b2516"), TEXT, 20)
	clue.custom_minimum_size = Vector2(0, 124)
	clue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clue.pressed.connect(toggle_direction)
	var cv := VBoxContainer.new()
	cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cv.offset_left = 18
	cv.offset_right = -18
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override("separation", 0)
	_clue_dir = _label("", 20, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_clue_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(_clue_dir)
	_clue_text = _label("", 28, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_clue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(_clue_text)
	clue.add_child(cv)
	bar.add_child(clue)
	var next := _icon(IconButton.Kind.NEXT, PANEL)
	next.custom_minimum_size = Vector2(88, 124)
	next.pressed.connect(next_clue)
	bar.add_child(next)
	v.add_child(bar)
	v.add_child(_build_keyboard())


func _build_keyboard() -> VBoxContainer:
	_keyboard = VBoxContainer.new()
	_keyboard.add_theme_constant_override("separation", 10)
	_keys = {}
	var rows := ["QWERTYUIOP", "ASDFGHJKLÑ" if lang == "es" else "ASDFGHJKL", "ZXCVBNM"]
	for r in rows.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 7)
		var row: String = rows[r]
		var pad := (10.0 - row.length() - (2.0 if r == 2 else 0.0)) * 0.5
		if pad > 0.0:
			h.add_child(_key_pad(pad))
		for ch in row:
			var b := Button.new()
			b.text = ch
			b.custom_minimum_size = Vector2(0, 98)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 34)
			_skin(b, PANEL_HI, TEXT, 14)
			_tight(b)
			b.pressed.connect(press_key.bind(ch))
			_keys[ch] = b
			h.add_child(b)
		if r == 2:
			var bs := IconButton.new(IconButton.Kind.BACKSPACE)
			bs.custom_minimum_size = Vector2(0, 98)
			bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bs.size_flags_stretch_ratio = 2.0
			_skin(bs, Color("39425f"), TEXT, 14)
			_tight(bs)
			bs.pressed.connect(press_backspace)
			_keys["⌫"] = bs
			h.add_child(bs)
		if pad > 0.0:
			h.add_child(_key_pad(pad))
		_keyboard.add_child(h)
	return _keyboard


## Keys are narrow: drop the horizontal content margins so ten fit a row.
func _tight(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		sb.content_margin_left = 0
		sb.content_margin_right = 0
	b.clip_text = true


func _key_pad(ratio: float) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func refresh() -> void:
	if board == null or _grid == null:
		return
	_grid.board = board
	_grid.queue_redraw()
	_title.text = (tr("DAILY_TAG") + " · " if is_daily else "") + tr("PUZZLE_N") % (index + 1)
	var e := board.current_clue()
	_clue_dir.text = "%d %s" % [e.number, tr("ACROSS") if e.dir == Puzzle.ACROSS else tr("DOWN")]
	_clue_text.text = e.clue
	_update_timer(true)


func _update_timer(force := false) -> void:
	if _timer == null or board == null:
		return
	var s := int(board.elapsed)
	if force or s != _shown_second:
		_shown_second = s
		_timer.text = Pack.format_time(board.elapsed)
		_timer.add_theme_color_override("font_color", GOOD if board.solved else MUTED)


func _process(delta: float) -> void:
	if screen != "game" or board == null:
		return
	if not board.solved and _overlay == null:
		board.elapsed += delta
		_update_timer()
	if _dirty:
		_since_save += delta
		if _since_save >= SAVE_DELAY:
			save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if screen == "game":
			save_now()


func _changed() -> void:
	_dirty = true
	_since_save = 0.0
	refresh()


func save_now() -> void:
	_dirty = false
	_since_save = 0.0
	if board == null or board.solved:
		return
	_settings().save_progress(board.puzzle.id, board.to_dict())


func _leave_game() -> void:
	if screen == "game" and board != null and not board.solved and board.filled_count() > 0:
		save_now()
	elif screen == "game" and board != null and not board.solved:
		_settings().save()


# --- input entry points --------------------------------------------------------

func tap_cell(i: int) -> void:
	if board == null or board.solved:
		return
	board.select_cell(i)
	refresh()


func toggle_direction() -> void:
	if board == null or board.solved:
		return
	board.toggle_dir()
	refresh()


func next_clue() -> void:
	if board and not board.solved:
		board.next_entry()
		refresh()


func prev_clue() -> void:
	if board and not board.solved:
		board.prev_entry()
		refresh()


func press_key(ch: String) -> void:
	if board == null or board.solved or _overlay != null:
		return
	board.type_letter(ch)
	_after_edit()


func press_backspace() -> void:
	if board == null or board.solved or _overlay != null:
		return
	board.backspace()
	_changed()


func _after_edit() -> void:
	if board.update_solved():
		_on_solved()
		return
	_changed()
	if board.is_full():
		toast(tr("NOT_QUITE"))


func toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = "  " + text + "  "
	_toast.reset_size()
	_toast.position = Vector2((_grid.size.x - _toast.size.x) * 0.5, _grid.size.y - _toast.size.y - 6)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- assist ----------------------------------------------------------------------

func show_assist() -> void:
	if board == null or board.solved:
		return
	var card := _sheet()
	var v: VBoxContainer = card.get_meta("box")
	v.add_child(_label(tr("ASSIST_TITLE"), 34))
	v.add_child(_label(tr("HELP_COUNT") % [board.checks, board.reveals], 22, MUTED))
	for item in [["CHECK_LETTER", false, false], ["CHECK_WORD", true, false], ["REVEAL_LETTER", false, true], ["REVEAL_WORD", true, true]]:
		var b := _button(tr(item[0]))
		b.pressed.connect(assist.bind(item[1], item[2]))
		v.add_child(b)
	var c := _button(tr("CANCEL"), false, 96, 28)
	_skin(c, PANEL, MUTED)
	c.pressed.connect(_close_overlay)
	v.add_child(c)


## word: whole current entry (else just the cursor cell); reveal: fill in.
func assist(word: bool, reveal: bool) -> void:
	_close_overlay()
	if board == null or board.solved:
		return
	if reveal:
		board.reveal(word)
		if board.update_solved():
			_on_solved()
			return
		if not word:
			board.type_letter(board.letters[board.cursor])
		_changed()
	else:
		var bad := board.check(word)
		_changed()
		toast(tr("N_WRONG") % bad if bad > 0 else tr("ALL_CORRECT"))


## Dimmed full-screen overlay with a centred card; the card's VBox is in meta "box".
func _sheet() -> PanelContainer:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_overlay = dim
	var card := PanelContainer.new()
	var sb := _style(PANEL, 28, Color("2f3756"))
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 40
	card.offset_right = -40
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	card.set_meta("box", v)
	card.pivot_offset = Vector2(320, 300)
	card.scale = Vector2(0.92, 0.92)
	dim.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "modulate:a", 1.0, 0.15)
	tw.tween_property(card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return card


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func show_howto() -> void:
	var card := _sheet()
	var v: VBoxContainer = card.get_meta("box")
	v.add_child(_label(tr("HOWTO"), 36, ACCENT))
	var t := _label(tr("HOWTO_TEXT").replace("\\n", "\n"), 25, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(560, 0)
	v.add_child(t)
	var c := _button(tr("CLOSE"), true)
	c.pressed.connect(_close_overlay)
	v.add_child(c)


# --- completion ---------------------------------------------------------------------

func _on_solved() -> void:
	var assisted := board.reveals > 0
	var record: bool = _settings().record_solve(board.puzzle.id, board.elapsed, assisted)
	_dirty = false
	refresh()
	_grid.wave = 0.0
	var tw := create_tween()
	tw.tween_property(_grid, "wave", 1.6, 0.9)
	tw.tween_callback(_show_done.bind(record, assisted))


func _show_done(record: bool, assisted: bool) -> void:
	if screen != "game":
		return
	var card := _sheet()
	_overlay.color = Color(0, 0, 0, 0.45)
	var v: VBoxContainer = card.get_meta("box")
	v.add_child(_label(tr("SOLVED"), 52, GOOD))
	v.add_child(_label(Pack.format_time(board.elapsed), 64, TEXT))
	var note := ""
	if assisted:
		note = tr("ASSISTED")
	elif record:
		note = tr("NEW_BEST")
	else:
		note = tr("BEST") % Pack.format_time(_settings().best_time(board.puzzle.id))
	var n := _label(note, 26, ACCENT if record else MUTED)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	v.add_child(_label(tr("HELP_COUNT") % [board.checks, board.reveals], 22, MUTED))
	var nb := _button(tr("NEXT"), true)
	nb.pressed.connect(open_next)
	v.add_child(nb)
	var lb := _button(tr("ALL"))
	lb.pressed.connect(show_list)
	v.add_child(lb)


## Next unsolved puzzle after the current one (wrapping), else just the next.
func open_next() -> void:
	for s in range(1, pack.size() + 1):
		var j := (index + s) % pack.size()
		if not _settings().is_solved(pack[j].id):
			open_puzzle(j)
			return
	open_puzzle((index + 1) % pack.size())
