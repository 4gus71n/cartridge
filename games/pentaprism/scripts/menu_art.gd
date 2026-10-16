class_name MenuArt
extends Control
## Decorative cluster of gem pentominoes that bob gently on the title screen.

var _clock := 0.0
var _pieces: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# shape, hues, offset in cells from the centre, phase
	for spec in [
		["F", [1, 2], Vector2(-4.5, -1.3), 0.0],
		["X", [3, 4], Vector2(0.0, -1.5), 1.3],
		["i3", [2], Vector2(4.5, -2.0), 2.1],
		["v3", [3], Vector2(-4.2, 1.8), 2.7],
		["U", [1, 3], Vector2(-0.3, 1.8), 1.9],
		["W", [4, 1], Vector2(4.0, 1.3), 0.7],
	]:
		var p := Pieces.make(spec[0], spec[1])
		_pieces.append({"p": p, "off": spec[2], "ph": spec[3]})


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var cell := minf(size.y / 6.4, size.x / 13.0)
	var c := size / 2.0 + Vector2(0, -0.1 * minf(size.y / 6.4, size.x / 13.0))
	for e in _pieces:
		var p: Pieces.Piece = e.p
		var bob := sin(_clock * 1.6 + e.ph) * cell * 0.12
		for i in p.cells.size():
			var pos: Vector2 = c + (e.off + Vector2(p.cells[i])) * cell + Vector2(-cell / 2.0, bob - cell / 2.0)
			Gem.draw(self, Rect2(pos, Vector2(cell, cell)).grow(-cell * 0.04), p.colors[i])
