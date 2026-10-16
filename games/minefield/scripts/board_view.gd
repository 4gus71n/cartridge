class_name BoardView
extends Control
## Draws a MineBoard and turns touches into game actions.
## Tap = dig (or flag in flag mode), long-press = flag, tap number = chord.

signal cell_tapped(cell: int)
signal cell_long_pressed(cell: int)

const LONG_PRESS := 0.35
const GAP := 3.0
const NUMBER_COLORS := [
	Color(0, 0, 0, 0),
	Color("#5eb3ff"), Color("#5ee38a"), Color("#ff6b6b"), Color("#c39bff"),
	Color("#ffb454"), Color("#4fe0d4"), Color("#f2f2f2"), Color("#9aa3b8"),
]
const COLOR_HIDDEN := Color("#28324f")
const COLOR_HIDDEN_TOP := Color("#34406a")
const COLOR_OPEN := Color("#121829")
const COLOR_EXPLODED := Color("#b3263a")
const COLOR_FLAG := Color("#ff4d6d")
const COLOR_MINE := Color("#0b0e18")

var board: MineBoard
var _cell := 32.0
var _origin := Vector2.ZERO
var _press_cell := -1
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _long_fired := false
var _reveal_at := {} # cell -> time it started revealing (animation)
var _clock := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)


func set_board(b: MineBoard) -> void:
	board = b
	_reveal_at.clear()
	_layout()
	queue_redraw()


## Animate cells in the order they were opened (a ripple from the tap).
func animate_reveal(cells: PackedInt32Array) -> void:
	for k in cells.size():
		_reveal_at[cells[k]] = _clock + minf(k * 0.006, 0.35)
	queue_redraw()


func _layout() -> void:
	if board == null:
		return
	_cell = floorf(minf(size.x / board.width, size.y / board.height))
	var used := Vector2(_cell * board.width, _cell * board.height)
	_origin = ((size - used) / 2.0).floor()
	queue_redraw()


func cell_at(pos: Vector2) -> int:
	if board == null:
		return -1
	var p := (pos - _origin) / _cell
	var x := int(floorf(p.x))
	var y := int(floorf(p.y))
	if x < 0 or y < 0 or x >= board.width or y >= board.height:
		return -1
	return board.index(x, y)


func _process(delta: float) -> void:
	_clock += delta
	if _press_cell >= 0 and not _long_fired and _clock - _press_time >= LONG_PRESS:
		_long_fired = true
		cell_long_pressed.emit(_press_cell)
	if not _reveal_at.is_empty():
		queue_redraw()
		if _clock > _latest_reveal() + 0.2:
			_reveal_at.clear()


func _latest_reveal() -> float:
	var latest := 0.0
	for t in _reveal_at.values():
		latest = maxf(latest, t)
	return latest


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var c := cell_at(mb.position)
			if c >= 0:
				cell_long_pressed.emit(c)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_cell = cell_at(mb.position)
				_press_pos = mb.position
				_press_time = _clock
				_long_fired = false
			else:
				if _press_cell >= 0 and not _long_fired:
					cell_tapped.emit(_press_cell)
				_press_cell = -1
			accept_event()
	elif event is InputEventMouseMotion and _press_cell >= 0:
		if (event as InputEventMouseMotion).position.distance_to(_press_pos) > _cell * 0.6:
			_press_cell = -1


func _draw() -> void:
	if board == null:
		return
	var lost := board.state == MineBoard.State.LOST
	var font_size := int(_cell * 0.58)
	var radius := maxf(3.0, _cell * 0.16)
	for i in board.size():
		var x := i % board.width
		var y := i / board.width
		var r := Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell)).grow(-GAP / 2.0)
		var center := r.get_center()
		var is_open := board.revealed[i] == 1
		var t := 1.0
		if is_open and _reveal_at.has(i):
			t = clampf((_clock - _reveal_at[i]) / 0.14, 0.0, 1.0)
			if t <= 0.0:
				is_open = false
		if not is_open:
			_rounded(r, COLOR_HIDDEN, radius)
			_rounded(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), COLOR_HIDDEN_TOP, radius, true)
			if i == _press_cell and not _long_fired and board.state == MineBoard.State.PLAYING:
				_rounded(r, Color(1, 1, 1, 0.08), radius)
			if board.flagged[i]:
				_draw_flag(center, _cell)
				if lost and not board.mines[i]:
					_draw_cross(center, _cell)
			elif lost and board.mines[i]:
				_draw_mine(center, _cell)
			continue
		var bg := COLOR_EXPLODED if i == board.exploded else COLOR_OPEN
		var rr := r.grow(-(1.0 - t) * _cell * 0.25)
		_rounded(rr, bg, radius)
		if board.mines[i]:
			_draw_mine(center, _cell)
		elif board.adjacent[i] > 0:
			var col: Color = NUMBER_COLORS[board.adjacent[i]]
			col.a = t
			var text := str(board.adjacent[i])
			var ascent := _font.get_ascent(font_size)
			var descent := _font.get_descent(font_size)
			var baseline := center.y + (ascent - descent) / 2.0
			draw_string(_font, Vector2(r.position.x, baseline), text,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, col)


func _rounded(r: Rect2, color: Color, radius: float, top_only := false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	if not top_only:
		sb.corner_radius_bottom_left = int(radius)
		sb.corner_radius_bottom_right = int(radius)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw_flag(c: Vector2, s: float) -> void:
	var pole_top := c + Vector2(-s * 0.12, -s * 0.28)
	var pole_bottom := c + Vector2(-s * 0.12, s * 0.26)
	draw_line(pole_top, pole_bottom, Color("#e6e9f2"), maxf(2.0, s * 0.06))
	draw_colored_polygon(PackedVector2Array([
		pole_top, pole_top + Vector2(s * 0.36, s * 0.13), pole_top + Vector2(0, s * 0.26),
	]), COLOR_FLAG)
	draw_line(c + Vector2(-s * 0.24, s * 0.26), c + Vector2(s * 0.02, s * 0.26),
		Color("#e6e9f2"), maxf(2.0, s * 0.06))


func _draw_mine(c: Vector2, s: float) -> void:
	var rad := s * 0.2
	for k in 4:
		var dir := Vector2.RIGHT.rotated(k * PI / 4.0)
		draw_line(c - dir * rad * 1.45, c + dir * rad * 1.45, COLOR_MINE, maxf(2.0, s * 0.07))
	draw_circle(c, rad, COLOR_MINE)
	draw_circle(c + Vector2(-rad, -rad) * 0.35, rad * 0.28, Color(1, 1, 1, 0.55))


func _draw_cross(c: Vector2, s: float) -> void:
	var d := s * 0.26
	var w := maxf(2.0, s * 0.07)
	draw_line(c + Vector2(-d, -d), c + Vector2(d, d), Color("#ffd166"), w)
	draw_line(c + Vector2(-d, d), c + Vector2(d, -d), Color("#ffd166"), w)
