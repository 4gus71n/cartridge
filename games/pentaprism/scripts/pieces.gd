class_name Pieces
extends RefCounted
## Piece catalogue + fair randomiser ("bag") for Pentaprism.
##
## The set is the 12 pentominoes plus two trominoes — deliberately no
## tetrominoes. Pentominoes carry two hues (3 + 2 cells), trominoes are a
## single "pure" hue. Cells are listed relative to an integer rotation pivot,
## y grows downwards (screen space).

const COLORS := 4 # hue ids are 1..COLORS (0 = empty)

const SHAPES := {
	"F": [[0, -1], [1, -1], [-1, 0], [0, 0], [0, 1]],
	"I": [[-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0]],
	"L": [[0, -2], [0, -1], [0, 0], [0, 1], [1, 1]],
	"N": [[0, -2], [0, -1], [-1, 0], [0, 0], [-1, 1]],
	"P": [[0, -1], [1, -1], [0, 0], [1, 0], [0, 1]],
	"T": [[-1, -1], [0, -1], [1, -1], [0, 0], [0, 1]],
	"U": [[-1, -1], [1, -1], [-1, 0], [0, 0], [1, 0]],
	"V": [[-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]],
	"W": [[-1, -1], [-1, 0], [0, 0], [0, 1], [1, 1]],
	"X": [[0, -1], [-1, 0], [0, 0], [1, 0], [0, 1]],
	"Y": [[0, -1], [-1, 0], [0, 0], [0, 1], [0, 2]],
	"Z": [[-1, -1], [0, -1], [0, 0], [0, 1], [1, 1]],
	"i3": [[-1, 0], [0, 0], [1, 0]],
	"v3": [[0, -1], [0, 0], [1, 0]],
}

## How many copies of each shape go into one bag (16 pieces per bag).
const WEIGHTS := {
	"F": 1, "I": 1, "L": 1, "N": 1, "P": 1, "T": 1, "U": 1, "V": 1,
	"W": 1, "X": 1, "Y": 1, "Z": 1, "i3": 2, "v3": 2,
}


## One falling piece: shape id, cell offsets around `pos`, a hue per cell.
class Piece:
	extends RefCounted
	var shape := ""
	var cells: Array[Vector2i] = []
	var colors := PackedInt32Array()
	var pos := Vector2i.ZERO

	func duplicate_piece() -> Piece:
		var p := Piece.new()
		p.shape = shape
		p.cells = cells.duplicate()
		p.colors = colors.duplicate()
		p.pos = pos
		return p

	## Cells after a quarter turn; dir = 1 clockwise, -1 counter-clockwise.
	func rotated_cells(dir: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in cells:
			out.append(Vector2i(-c.y, c.x) if dir > 0 else Vector2i(c.y, -c.x))
		return out

	func min_y() -> int:
		var m := 99
		for c in cells:
			m = mini(m, c.y)
		return m


static func base_cells(shape: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in SHAPES[shape]:
		out.append(Vector2i(c[0], c[1]))
	return out


static func bag_size() -> int:
	var n := 0
	for k in WEIGHTS:
		n += WEIGHTS[k]
	return n


## Builds a piece in spawn orientation. `hues` = [a] (mono) or [a, b].
static func make(shape: String, hues: Array) -> Piece:
	var p := Piece.new()
	p.shape = shape
	p.cells = base_cells(shape)
	# Reading order (top-to-bottom, left-to-right): first ceil(n/2) cells get
	# hue a, the rest hue b, so each hue forms a connected-ish patch.
	var order := range(p.cells.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		var ci: Vector2i = p.cells[i]
		var cj: Vector2i = p.cells[j]
		return ci.y < cj.y or (ci.y == cj.y and ci.x < cj.x))
	p.colors.resize(p.cells.size())
	var split := (p.cells.size() + 1) / 2
	for k in order.size():
		var hue: int = hues[0] if (k < split or hues.size() == 1) else hues[1]
		p.colors[order[k]] = hue
	return p


## Fair randomiser: shapes come from a shuffled bag (each shape exactly
## WEIGHTS[shape] times per bag); hue pairs and pure hues also come from
## their own shuffled bags so no colour is starved.
class Bag:
	extends RefCounted
	var rng := RandomNumberGenerator.new()
	var _shapes: Array[String] = []
	var _pairs: Array = []
	var _monos: Array = []

	func _init(seed_value: int = -1) -> void:
		if seed_value < 0:
			rng.randomize()
		else:
			rng.seed = seed_value

	func next_shape() -> String:
		if _shapes.is_empty():
			for k in Pieces.WEIGHTS:
				for n in Pieces.WEIGHTS[k]:
					_shapes.append(k)
			_shuffle(_shapes)
		return _shapes.pop_back()

	func next_pair() -> Array:
		if _pairs.is_empty():
			for a in range(1, Pieces.COLORS + 1):
				for b in range(a + 1, Pieces.COLORS + 1):
					_pairs.append([a, b] if rng.randi() % 2 == 0 else [b, a])
			_shuffle(_pairs)
		return _pairs.pop_back()

	func next_mono() -> int:
		if _monos.is_empty():
			for a in range(1, Pieces.COLORS + 1):
				_monos.append(a)
			_shuffle(_monos)
		return _monos.pop_back()

	func next_piece() -> Piece:
		var shape := next_shape()
		var hues: Array = [next_mono()] if Pieces.SHAPES[shape].size() < 5 else next_pair()
		return Pieces.make(shape, hues)

	func _shuffle(a: Array) -> void:
		for i in range(a.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = a[i]
			a[i] = a[j]
			a[j] = t
