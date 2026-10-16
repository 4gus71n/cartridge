class_name BoardView
extends Control
## Draws a PrismBoard with all the juice (fall slides, clear flashes,
## particles, popups, light screen shake) and turns touches into actions:
## drag sideways = move, tap = rotate, drag down = soft drop,
## flick down = hard drop, flick up = hold.

signal action(name: String)

const WELL := Color("#110f24")
const WELL_EDGE := Color("#8f6bff")
const CLEAR_TIME := 0.42
const FALL_TIME := 0.13

var board: PrismBoard
var _cell := 40.0
var _origin := Vector2.ZERO
var _clock := 0.0
var _font: Font

var _falls := {} # index -> {"dy": px, "t0": time}
var _clearing := [] # {"cell": Vector2i, "hue": int, "t0": float}
var _rows := [] # {"y": int, "t0": float}
var _particles := [] # {"p","v","life","max","col","size"}
var _popups := [] # {"text","p","t0","col","size"}
var _flash := {} # index -> t0 (lock glow)
var _shake := 0.0
var _piece_vis := Vector2.ZERO
var _piece_ref: Pieces.Piece
var _over_t0 := -1.0

# Gesture state.
var _pressing := false
var _start := Vector2.ZERO
var _anchor := Vector2.ZERO
var _t0_ms := 0
var _axis := 0 # 0 undecided, 1 horizontal, 2 vertical


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)


func set_board(b: PrismBoard) -> void:
	board = b
	_falls.clear()
	_clearing.clear()
	_rows.clear()
	_particles.clear()
	_popups.clear()
	_flash.clear()
	_over_t0 = -1.0
	_piece_ref = null
	_layout()


func _layout() -> void:
	if board == null:
		return
	_cell = floorf(minf((size.x - 8.0) / board.width, (size.y - 8.0) / board.height))
	var used := Vector2(_cell * board.width, _cell * board.height)
	_origin = ((size - used) / 2.0).floor()
	queue_redraw()


func cell_size() -> float:
	return _cell


func cell_rect(x: float, y: float) -> Rect2:
	return Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell)).grow(-_cell * 0.04)


# --- effects API ------------------------------------------------------------

func animate_falls(falls: Array) -> void:
	for f in falls:
		var from_y: int = f[0] / board.width
		var to_y: int = f[1] / board.width
		_falls[f[1]] = {"dy": (to_y - from_y) * _cell, "t0": _clock}


func animate_lock(cells: Array) -> void:
	for i in cells:
		_flash[i] = _clock


func animate_clear(step: Dictionary) -> void:
	var cells: Dictionary = step.cells
	var chain: int = step.chain
	for i in cells:
		var cell := Vector2i(i % board.width, i / board.width)
		_clearing.append({"cell": cell, "hue": cells[i], "t0": _clock})
		_burst(cell_rect(cell.x, cell.y).get_center(), Gem.color(cells[i]), 7 + chain * 2)
	for y in step.rows:
		_rows.append({"y": y, "t0": _clock})
	shake(4.0 + chain * 2.5 + step.rows.size() * 3.0)
	# Popup at the centre of the cleared cells.
	var c := Vector2.ZERO
	for i in cells:
		c += cell_rect(i % board.width, i / board.width).get_center()
	c /= maxf(1.0, cells.size())
	popup("+%d" % step.points, c, Color.WHITE, 40)
	if chain > 1:
		popup(tr("CHAIN") % chain, c + Vector2(0, -_cell * 1.1), Color("#ffd166"), 44 + chain * 4)
	if not step.rows.is_empty():
		popup(tr("PRISM_LINE"), c + Vector2(0, _cell * 1.0), Color("#7af0d0"), 34)


func animate_hard_drop(piece: Pieces.Piece, from_y: int) -> void:
	for i in piece.cells.size():
		var c := piece.cells[i]
		var top := cell_rect(piece.pos.x + c.x, from_y + c.y).get_center()
		var bottom := cell_rect(piece.pos.x + c.x, piece.pos.y + c.y).get_center()
		for k in 3:
			var p := top.lerp(bottom, randf())
			_particles.append({"p": p, "v": Vector2(randf_range(-20, 20), randf_range(-60, -10)),
				"life": 0.35, "max": 0.35, "col": Color(Gem.color(piece.colors[i]), 0.7), "size": _cell * 0.1})
	shake(3.0)


func animate_game_over() -> void:
	_over_t0 = _clock
	shake(10.0)


func shake(amount: float) -> void:
	_shake = minf(16.0, maxf(_shake, amount))


func popup(text: String, p: Vector2, col: Color, font_size: int) -> void:
	_popups.append({"text": text, "p": p, "t0": _clock, "col": col, "size": font_size})


func _burst(p: Vector2, col: Color, n: int) -> void:
	for k in n:
		var ang := randf() * TAU
		var spd := randf_range(120, 420)
		var life := randf_range(0.35, 0.75)
		_particles.append({"p": p, "v": Vector2(cos(ang), sin(ang)) * spd - Vector2(0, 120),
			"life": life, "max": life, "col": col.lightened(randf() * 0.4), "size": randf_range(0.07, 0.16) * _cell})


func busy() -> bool:
	return not _clearing.is_empty() or not _falls.is_empty()


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_shake = maxf(0.0, _shake - delta * 40.0)
	for p in _particles:
		p.life -= delta
		p.v.y += 900.0 * delta
		p.v *= 1.0 - 1.5 * delta
		p.p += p.v * delta
	_particles = _particles.filter(func(p: Dictionary) -> bool: return p.life > 0.0)
	_clearing = _clearing.filter(func(c: Dictionary) -> bool: return _clock - c.t0 < CLEAR_TIME)
	_rows = _rows.filter(func(r: Dictionary) -> bool: return _clock - r.t0 < 0.5)
	_popups = _popups.filter(func(p: Dictionary) -> bool: return _clock - p.t0 < 1.0)
	for k in _falls.keys():
		if _clock - _falls[k].t0 > FALL_TIME:
			_falls.erase(k)
	for k in _flash.keys():
		if _clock - _flash[k] > 0.3:
			_flash.erase(k)
	if board and board.current:
		var target := Vector2(board.current.pos)
		if board.current != _piece_ref:
			_piece_ref = board.current
			_piece_vis = target
		else:
			_piece_vis = _piece_vis.lerp(target, minf(1.0, delta * 28.0))
			if _piece_vis.distance_to(target) < 0.02:
				_piece_vis = target
	queue_redraw()


# --- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_pressing = true
			_start = mb.position
			_anchor = mb.position
			_t0_ms = Time.get_ticks_msec()
			_axis = 0
		elif _pressing:
			_pressing = false
			_release(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		_drag((event as InputEventMouseMotion).position)
		accept_event()


func _drag(pos: Vector2) -> void:
	var d := pos - _start
	if _axis == 0 and d.length() > 18.0:
		_axis = 1 if absf(d.x) >= absf(d.y) else 2
	var step := maxf(24.0, _cell * 0.85)
	if _axis == 1:
		while pos.x - _anchor.x >= step:
			_anchor.x += step
			action.emit("right")
		while _anchor.x - pos.x >= step:
			_anchor.x -= step
			action.emit("left")
	elif _axis == 2:
		while pos.y - _anchor.y >= _cell:
			_anchor.y += _cell
			action.emit("soft")


func _release(pos: Vector2) -> void:
	print("REL axis=", _axis, " d=", pos - _start, " dt=", (Time.get_ticks_msec() - _t0_ms))
	var dt := maxf(0.016, (Time.get_ticks_msec() - _t0_ms) / 1000.0)
	var d := pos - _start
	if _axis == 0:
		if dt < 0.4:
			action.emit("rotate")
	elif _axis == 2:
		var v := d.y / dt
		if d.y > _cell * 1.2 and v > 900.0:
			action.emit("hard")
		elif d.y < -_cell * 1.2 and v < -600.0:
			action.emit("hold")


# --- drawing --------------------------------------------------------------------

func _draw() -> void:
	if board == null:
		return
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	draw_set_transform(off)
	var well := Rect2(_origin, Vector2(board.width, board.height) * _cell)
	_rounded(well.grow(6), WELL, 14)
	# Danger glow: tint the top rows when a column gets close to the top.
	var peak := _stack_peak()
	if peak <= 4:
		var a := 0.08 + 0.06 * sin(_clock * 6.0)
		draw_rect(Rect2(well.position, Vector2(well.size.x, _cell * 3)), Color(1, 0.2, 0.35, a))
	# Faint dot lattice instead of grid lines.
	for y in board.height:
		for x in board.width:
			draw_circle(_origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * _cell, maxf(1.5, _cell * 0.045),
				Color(1, 1, 1, 0.07))
	_edge(well.grow(6))
	# Locked gems.
	for i in board.grid.size():
		var hue := board.grid[i]
		if hue == 0:
			continue
		var x := i % board.width
		var y := i / board.width
		var r := cell_rect(x, y)
		if _falls.has(i):
			var t: float = clampf((_clock - _falls[i].t0) / FALL_TIME, 0.0, 1.0)
			r.position.y -= _falls[i].dy * (1.0 - t * t)
		var flash := 0.0
		if _flash.has(i):
			flash = 0.55 * (1.0 - clampf((_clock - _flash[i]) / 0.3, 0.0, 1.0))
		var grey := 0.0
		if _over_t0 >= 0.0:
			grey = clampf((_clock - _over_t0) * 3.0 - (board.height - y) * 0.08, 0.0, 1.0)
		Gem.draw(self, r, hue, flash, 1.0, grey)
	# Ghost + active piece.
	var p := board.current
	if p != null and board.state == PrismBoard.State.PLAYING:
		var gy := board.ghost_y()
		if gy != p.pos.y:
			for i in p.cells.size():
				var gc := p.cells[i]
				if gy + gc.y >= 0:
					Gem.draw_ghost(self, cell_rect(p.pos.x + gc.x, gy + gc.y), p.colors[i])
		var vis := _piece_vis if _piece_ref == p else Vector2(p.pos)
		for i in p.cells.size():
			var c := p.cells[i]
			if vis.y + c.y > -1.0:
				Gem.draw(self, cell_rect(vis.x + c.x, vis.y + c.y), p.colors[i])
	# Clearing gems: white flash, then pop.
	for c in _clearing:
		var t: float = (_clock - c.t0) / CLEAR_TIME
		var r := cell_rect(c.cell.x, c.cell.y)
		if t < 0.4:
			Gem.draw(self, r, c.hue, t / 0.4 * 0.85)
		else:
			var k := (t - 0.4) / 0.6
			Gem.draw(self, r.grow(-r.size.x * 0.5 * k), c.hue, 0.85, 1.0 - k)
			draw_arc(r.get_center(), r.size.x * (0.4 + k * 0.6), 0, TAU, 24,
				Color(Gem.color(c.hue).lightened(0.4), 1.0 - k), maxf(2.0, _cell * 0.06))
	for rr in _rows:
		var t: float = (_clock - rr.t0) / 0.5
		var band := Rect2(_origin + Vector2(0, rr.y * _cell), Vector2(board.width * _cell, _cell))
		draw_rect(band.grow_individual(0, _cell * 0.3 * t, 0, _cell * 0.3 * t), Color(1, 1, 1, 0.5 * (1.0 - t)))
	for pt in _particles:
		var a: float = clampf(pt.life / pt.max, 0.0, 1.0)
		var s: float = pt.size
		draw_rect(Rect2(pt.p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(pt.col, a))
	for pp in _popups:
		var t: float = (_clock - pp.t0)
		var a := clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
		var scale := 1.0 + 0.25 * maxf(0.0, 1.0 - t * 6.0)
		var fs := int(pp.size * scale)
		var pos: Vector2 = pp.p + Vector2(0, -60.0 * t)
		var w := 600.0
		var baseline := pos.y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0
		var px := clampf(pos.x - w / 2.0, -w / 2.0 + 120, size.x - w / 2.0 - 120)
		draw_string_outline(_font, Vector2(px, baseline), pp.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
			8, Color(0.04, 0.03, 0.1, a * 0.85))
		draw_string(_font, Vector2(px, baseline), pp.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(pp.col, a))
	draw_set_transform(Vector2.ZERO)


func _stack_peak() -> int:
	for i in board.grid.size():
		if board.grid[i] != 0:
			return i / board.width
	return board.height


func _edge(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(3)
	sb.border_color = Color(WELL_EDGE, 0.55)
	sb.set_corner_radius_all(14)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _rounded(r: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
