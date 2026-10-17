class_name GridView
extends Control
## Draws a Board (cells, numbers, letters, highlight, check/reveal marks) and
## reports taps. Also used, non-interactive, as the menu logo.

signal cell_tapped(index: int)

const BOARD_BG := Color("0f1322")
const CELL := Color("eef0f6")
const ENTRY := Color("ffe2a6")
const CURSOR := Color("ffb547")
const INK := Color("141826")
const NUM := Color("4a5168")
const WRONG := Color("d9363e")
const REVEAL := Color("2f6fd6")
const SOLVED := Color("a5ecc0")

var board: Board:
	set(v):
		board = v
		queue_redraw()
## Draw the active entry / cursor highlight.
var show_cursor := true
## Celebration wave position (0 → ~1.5 sweeps the grid diagonally).
var wave := -1.0:
	set(v):
		wave = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if show_cursor else Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func cell_size() -> float:
	if board == null:
		return 0.0
	var n := maxi(board.puzzle.width, board.puzzle.height)
	return floorf(minf(size.x, size.y) / n)


func grid_rect() -> Rect2:
	var cs := cell_size()
	var w := cs * board.puzzle.width
	var h := cs * board.puzzle.height
	return Rect2(((size - Vector2(w, h)) * 0.5).floor(), Vector2(w, h))


## Centre of cell `i` in local coordinates.
func cell_center(i: int) -> Vector2:
	var cs := cell_size()
	var r := grid_rect()
	return r.position + Vector2((i % board.puzzle.width + 0.5) * cs, (i / board.puzzle.width + 0.5) * cs)


func cell_at(p: Vector2) -> int:
	if board == null:
		return -1
	var r := grid_rect()
	if not r.has_point(p):
		return -1
	var cs := cell_size()
	var c := int((p.x - r.position.x) / cs)
	var row := int((p.y - r.position.y) / cs)
	return board.puzzle.index(clampi(row, 0, board.puzzle.height - 1), clampi(c, 0, board.puzzle.width - 1))


func _gui_input(event: InputEvent) -> void:
	if not show_cursor or board == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := cell_at(event.position)
		if i >= 0 and not board.puzzle.is_block(i):
			cell_tapped.emit(i)
			accept_event()


func _draw() -> void:
	if board == null:
		return
	var p := board.puzzle
	var cs := cell_size()
	var gr := grid_rect()
	var bg := StyleBoxFlat.new()
	bg.bg_color = BOARD_BG
	bg.set_corner_radius_all(int(cs * 0.12))
	bg.border_color = Color("2a3150")
	bg.set_border_width_all(3)
	draw_style_box(bg, gr.grow(8))
	var font := get_theme_default_font()
	var entry_cells: Array = []
	if show_cursor and not board.solved:
		entry_cells = p.entries[board.current_entry()].cells
	var gap := maxf(2.0, cs * 0.035)
	var span := float(p.width + p.height - 2)
	for i in p.cell_count():
		if p.is_block(i):
			continue
		var r := i / p.width
		var c := i % p.width
		var rect := Rect2(gr.position + Vector2(c * cs, r * cs), Vector2(cs, cs)).grow(-gap * 0.5)
		var col := CELL
		if board.solved:
			col = SOLVED
			if wave >= 0.0:
				var t := wave - (r + c) / maxf(span, 1.0)
				var glow := clampf(1.0 - absf(t) * 4.0, 0.0, 1.0)
				col = SOLVED.lerp(Color.WHITE, glow * 0.7)
				rect = rect.grow(glow * cs * 0.05)
		elif show_cursor and i == board.cursor:
			col = CURSOR
		elif i in entry_cells:
			col = ENTRY
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(cs * 0.08))
		draw_style_box(sb, rect)
		var n := p.numbers[i]
		if n > 0:
			var fs := int(cs * 0.22)
			draw_string(font, rect.position + Vector2(cs * 0.07, fs * 0.95 + cs * 0.02), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NUM)
		var ch := board.letters[i]
		if ch != "":
			var fs := int(cs * 0.56)
			var ink := INK
			if board.revealed[i]:
				ink = REVEAL
			elif board.wrong[i]:
				ink = WRONG
			var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var base := rect.position.y + rect.size.y * 0.5 + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.15 + cs * 0.06
			draw_string(font, Vector2(rect.get_center().x - w * 0.5, base), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		if board.revealed[i]:
			var e := rect.end
			var k := cs * 0.24
			draw_colored_polygon(PackedVector2Array([Vector2(e.x - k, rect.position.y), Vector2(e.x, rect.position.y), Vector2(e.x, rect.position.y + k)]), REVEAL)
		elif board.wrong[i] and ch != "":
			draw_line(rect.position + Vector2(cs * 0.12, cs * 0.85), rect.position + Vector2(cs * 0.85, cs * 0.12), Color(WRONG, 0.8), maxf(2.0, cs * 0.04), true)
