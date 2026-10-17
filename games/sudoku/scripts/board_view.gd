class_name BoardView
extends Control
## Draws the 9x9 grid (givens, entries, pencil marks, highlights) and turns
## taps into cell selections. All game state lives in SudokuGame.

signal cell_pressed(cell: int)

const PANEL := Color("#151a2c")
const CELL_ALT := Color("#1a2036")
const LINE := Color("#2b3352")
const THICK := Color("#6a7398")
const TEXT := Color("#eef1ff")
const MUTED := Color("#8d93b4")
const ACCENT := Color("#ffa53d")
const ENTRY := Color("#ffc47a")
const HINTED := Color("#7fd6ff")
const ERROR := Color("#ff5d6c")

var game: SudokuGame
var selected := -1
var mistake_check := true
var _pops := {} ## cell -> seconds left of the "placed" pop
var _flash := {} ## cell -> seconds left of a unit-complete / win flash
var _shake := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func cell_size() -> float:
	return floorf(minf(size.x, size.y) / 9.0)


func origin() -> Vector2:
	var side := cell_size() * 9.0
	return ((size - Vector2(side, side)) / 2.0).floor()


func cell_rect(i: int) -> Rect2:
	var cs := cell_size()
	return Rect2(origin() + Vector2(i % 9, i / 9) * cs, Vector2(cs, cs))


## Cell under a local position, or -1.
func cell_at(pos: Vector2) -> int:
	var p := (pos - origin()) / cell_size()
	if p.x < 0 or p.y < 0 or p.x >= 9 or p.y >= 9:
		return -1
	return int(p.y) * 9 + int(p.x)


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		pos = event.position
	if pressed:
		var c := cell_at(pos)
		if c >= 0:
			cell_pressed.emit(c)
			accept_event()


func pop(cell: int) -> void:
	_pops[cell] = 0.25
	queue_redraw()


func flash(cells: Array, delay_step := 0.0) -> void:
	for k in cells.size():
		_flash[cells[k]] = 0.55 + k * delay_step
	queue_redraw()


func shake() -> void:
	_shake = 0.3


func _process(delta: float) -> void:
	if _pops.is_empty() and _flash.is_empty() and _shake <= 0.0:
		return
	for d in [_pops, _flash]:
		for k in d.keys():
			d[k] -= delta
			if d[k] <= 0.0:
				d.erase(k)
	_shake = maxf(0.0, _shake - delta)
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var cs := cell_size()
	var o := origin()
	if _shake > 0.0:
		o.x += sin(_shake * 60.0) * 8.0 * (_shake / 0.3)
	var side := cs * 9.0
	var font := get_theme_default_font()
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL
	bg.set_corner_radius_all(14)
	bg.border_color = THICK
	bg.set_border_width_all(3)
	bg.anti_aliasing = true
	draw_style_box(bg, Rect2(o - Vector2(3, 3), Vector2(side + 6, side + 6)))

	var sel_val := 0
	if selected >= 0:
		sel_val = game.values[selected]
	for i in 81:
		var r := Rect2(o + Vector2(i % 9, i / 9) * cs, Vector2(cs, cs))
		var fill := Color(0, 0, 0, 0)
		if SudokuGrid.box(i) % 2 == 1:
			fill = CELL_ALT
		if selected >= 0 and (SudokuGrid.row(i) == SudokuGrid.row(selected) or SudokuGrid.col(i) == SudokuGrid.col(selected) or SudokuGrid.box(i) == SudokuGrid.box(selected)):
			fill = Color("#232b47")
		if sel_val != 0 and game.values[i] == sel_val:
			fill = Color(ACCENT, 0.24)
		if mistake_check and game.is_wrong(i):
			fill = Color(ERROR, 0.2)
		if i == selected:
			fill = Color(ACCENT, 0.42)
		if _flash.has(i):
			var t: float = clampf(_flash[i] / 0.55, 0.0, 1.0)
			fill = fill.lerp(Color(ACCENT, 0.7), sin(t * PI) * 0.8)
		if fill.a > 0.0:
			draw_rect(r.grow(-0.5), fill)

	# Grid lines: thin cell lines, then thick box lines on top.
	for k in range(1, 9):
		if k % 3 == 0:
			continue
		var x := o.x + k * cs
		var y := o.y + k * cs
		draw_line(Vector2(x, o.y), Vector2(x, o.y + side), LINE, 2.0)
		draw_line(Vector2(o.x, y), Vector2(o.x + side, y), LINE, 2.0)
	for k in [3, 6]:
		var x: float = o.x + k * cs
		var y: float = o.y + k * cs
		draw_line(Vector2(x, o.y), Vector2(x, o.y + side), THICK, 4.0)
		draw_line(Vector2(o.x, y), Vector2(o.x + side, y), THICK, 4.0)
	if selected >= 0:
		var sr := Rect2(o + Vector2(selected % 9, selected / 9) * cs, Vector2(cs, cs))
		draw_rect(sr.grow(-2.0), ACCENT, false, 3.0)

	# Digits and pencil marks.
	var big := int(cs * 0.62)
	var small := int(cs * 0.27)
	for i in 81:
		var r := Rect2(o + Vector2(i % 9, i / 9) * cs, Vector2(cs, cs))
		var v: int = game.values[i]
		if v != 0:
			var col := TEXT
			if not game.is_given(i):
				col = HINTED if game.hinted[i] == 1 else ENTRY
			if mistake_check and game.is_wrong(i):
				col = ERROR
			var fs := big
			if _pops.has(i):
				fs = int(big * (1.0 + 0.35 * sin(clampf(_pops[i] / 0.25, 0.0, 1.0) * PI)))
			_centered(font, r, str(v), fs, col)
		elif game.notes[i] != 0:
			var sub := cs / 3.0
			for d in range(1, 10):
				if game.notes[i] & (1 << d):
					var nr := Rect2(r.position + Vector2((d - 1) % 3, (d - 1) / 3) * sub, Vector2(sub, sub))
					var nc := ACCENT if d == sel_val else MUTED
					if d == sel_val:
						draw_circle(nr.get_center(), sub * 0.42, Color(ACCENT, 0.22))
					_centered(font, nr, str(d), small, nc)


func _centered(font: Font, r: Rect2, text: String, fs: int, col: Color) -> void:
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	var y := r.position.y + (r.size.y + asc - desc) / 2.0
	draw_string(font, Vector2(r.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
