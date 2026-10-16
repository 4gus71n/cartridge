class_name PiecePreview
extends Control
## Small panel showing one or more pieces (hold slot / next queue).
## Pieces are laid out horizontally in equal slots and drawn with Gem.

signal pressed

var title := ""
var pieces: Array = [] # Pieces.Piece or null
var dimmed := false
var first_big := true # first slot is drawn larger (the very next piece)
var _font: Font
var _down := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_pieces(list: Array, dim := false) -> void:
	pieces = list
	dimmed = dim
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
		queue_redraw()
		accept_event()


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1b1838") if not _down else Color("#2a2550")
	sb.set_corner_radius_all(18)
	sb.anti_aliasing = true
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var fs := 20
	draw_string(_font, Vector2(0, 26), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color("#8a86b0"))
	var area := Rect2(Vector2(8, 34), size - Vector2(16, 42))
	if pieces.is_empty():
		return
	var n := pieces.size()
	var weights := []
	var total := 0.0
	for k in n:
		var w := 1.4 if (first_big and k == 0 and n > 1) else 1.0
		weights.append(w)
		total += w
	var x := area.position.x
	for k in n:
		var slot_w: float = area.size.x * weights[k] / total
		var slot := Rect2(Vector2(x, area.position.y), Vector2(slot_w, area.size.y))
		x += slot_w
		var p: Pieces.Piece = pieces[k]
		if p == null:
			continue
		var mn := Vector2i(99, 99)
		var mx := Vector2i(-99, -99)
		for c in p.cells:
			mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
			mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
		var dims := Vector2(mx - mn + Vector2i.ONE)
		var cell := floorf(minf(slot.size.x / maxf(dims.x, 3.0), slot.size.y / maxf(dims.y, 3.0)))
		cell = minf(cell, 30.0 if k == 0 else 24.0)
		var origin := slot.get_center() - dims * cell / 2.0
		for i in p.cells.size():
			var c := p.cells[i] - mn
			var r := Rect2(origin + Vector2(c) * cell, Vector2(cell, cell)).grow(-1)
			Gem.draw(self, r, p.colors[i], 0.0, 0.35 if dimmed else (1.0 if k == 0 else 0.8))
