class_name MapView
extends Control
## Code-drawn glyph-on-tile dungeon view, camera centred on the player.
## Input: tap a tile, swipe for one step, long-press to inspect.

signal tapped(cell: Vector2i)
signal swiped(dir: Vector2i)
signal held(cell: Vector2i)

const BG := Color("#0b0a10")
const FLOOR := Color("#1d1a28")
const FLOOR_DOT := Color("#353047")
const CORR := Color("#17151f")
const WALL_TOP := Color("#4a4263")
const WALL_FACE := Color("#2c2740")
const DOOR := Color("#b9773f")
const ACCENT := Color("#ff9e3d")
const PLAYER := Color("#fff1d6")
const COLS := 12.0

var run: Run
var tile := 60.0
var cam := Vector2.ZERO
var aiming := false
var font: Font
var floaters: Array = [] # {p: Vector2 cell, s: text, c: Color, t: age}
var bolts: Array = [] # {a: Vector2i, b: Vector2i, c: Color, t: age, z: bool}
var flashes := {} # monster id -> age
var bursts: Array = [] # {p: Vector2i, t: age, c: Color}

var _down := false
var _moved := false
var _held := false
var _down_pos := Vector2.ZERO
var _down_t := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.7
	font = fv


func snap() -> void:
	if run != null:
		cam = Vector2(run.px, run.py)
	queue_redraw()


func _process(delta: float) -> void:
	tile = floorf(size.x / COLS)
	var busy := false
	if run != null:
		var target := Vector2(run.px, run.py)
		if cam.distance_to(target) > 6.0:
			cam = target
		elif cam.distance_squared_to(target) > 0.0001:
			cam = cam.lerp(target, minf(1.0, delta * 16.0))
			busy = true
		else:
			cam = target
	for f in floaters:
		f.t += delta
	floaters = floaters.filter(func(f: Dictionary) -> bool: return f.t < 0.9)
	for b in bolts:
		b.t += delta
	bolts = bolts.filter(func(b: Dictionary) -> bool: return b.t < 0.28)
	for b in bursts:
		b.t += delta
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.t < 0.45)
	for k in flashes.keys():
		flashes[k] += delta
		if flashes[k] > 0.25:
			flashes.erase(k)
	busy = busy or not floaters.is_empty() or not bolts.is_empty() or not flashes.is_empty() or not bursts.is_empty()
	if _down and not _held and not _moved and Time.get_ticks_msec() - _down_t > 450:
		_held = true
		held.emit(cell_at(_down_pos))
	if busy:
		queue_redraw()


## Turns Run.events into animations.
func consume_events() -> void:
	if run == null:
		return
	for e in run.events:
		match e.e:
			"dmg":
				var player: bool = int(e.id) == -1
				floaters.append({"p": Vector2(e.x, e.y), "s": "-%d" % e.n, "c": Color("#ff6b5e") if player else Color("#ffe08a"), "t": 0.0})
				if not player:
					flashes[e.id] = 0.0
			"heal":
				floaters.append({"p": Vector2(e.x, e.y), "s": "+%d" % e.n, "c": Color("#8fe388"), "t": 0.0})
			"miss":
				floaters.append({"p": Vector2(e.x, e.y), "s": "·", "c": Color("#9a95ad"), "t": 0.0})
			"bolt":
				bolts.append({"a": e.a, "b": e.b, "c": Color(e.c), "t": 0.0, "z": e.get("z", false)})
			"burst":
				bursts.append({"p": Vector2i(e.x, e.y), "t": 0.0, "c": Color("#ff7a3d")})
			"kill":
				bursts.append({"p": Vector2i(e.x, e.y), "t": 0.0, "c": Color(e.c)})
			"level":
				floaters.append({"p": Vector2(run.px, run.py), "s": "LV %d" % run.lvl, "c": ACCENT, "t": 0.0})
	run.events.clear()
	queue_redraw()


func cell_origin(c: Vector2) -> Vector2:
	return size * 0.5 + (c - cam) * tile - Vector2(tile, tile) * 0.5


func cell_at(p: Vector2) -> Vector2i:
	var f := (p - size * 0.5) / tile + cam
	return Vector2i(floori(f.x + 0.5), floori(f.y + 0.5))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_moved = false
			_held = false
			_down_pos = event.position
			_down_t = Time.get_ticks_msec()
		elif _down:
			_down = false
			if _held:
				return
			var d: Vector2 = event.position - _down_pos
			if d.length() > tile * 0.7:
				swiped.emit(dir8(d))
			else:
				tapped.emit(cell_at(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _down:
		if (event.position - _down_pos).length() > 22.0:
			_moved = true


static func dir8(d: Vector2) -> Vector2i:
	var a := fposmod(d.angle(), TAU)
	var k := int(roundf(a / (TAU / 8.0))) % 8
	return [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)][k]


func _shade(c: Color, lit: bool, dist: float) -> Color:
	if lit:
		var f := 1.0 - 0.38 * clampf(dist / float(Run.FOV_RADIUS), 0.0, 1.0)
		return Color(c.r * f, c.g * f, c.b * f, c.a)
	var g := (c.r + c.g + c.b) / 3.0
	var m := Color(lerpf(c.r, g, 0.6), lerpf(c.g, g, 0.6), lerpf(c.b, g, 0.6) + 0.02, c.a)
	return Color(m.r * 0.5, m.g * 0.5, m.b * 0.55, c.a)


func glyph(pos: Vector2, g: String, col: Color, fsize: int) -> void:
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	var base := pos + Vector2(-tile * 0.5, (asc - desc) * 0.5)
	draw_string(font, base, g, HORIZONTAL_ALIGNMENT_CENTER, tile, fsize, col)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if run == null or run.lv == null:
		return
	var lv := run.lv
	var half := size / tile * 0.5 + Vector2(2, 2)
	var x0 := maxi(0, floori(cam.x - half.x))
	var x1 := mini(Level.W - 1, ceili(cam.x + half.x))
	var y0 := maxi(0, floori(cam.y - half.y))
	var y1 := mini(Level.H - 1, ceili(cam.y + half.y))
	var gsize := int(tile * 0.62)
	var me := Vector2(run.px, run.py)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := Level.idx(x, y)
			if lv.seen[i] == 0:
				continue
			var lit := run.fov[i] == 1
			var d := me.distance_to(Vector2(x, y))
			var o := cell_origin(Vector2(x, y))
			var r := Rect2(o, Vector2(tile, tile))
			var c := o + Vector2(tile, tile) * 0.5
			var t := lv.tiles[i]
			match t:
				Level.WALL:
					var open_below := lv.passable(x, y + 1) and lv.seen[Level.idx(x, mini(y + 1, Level.H - 1))] == 1
					draw_rect(r, _shade(WALL_TOP, lit, d))
					if open_below:
						draw_rect(Rect2(o + Vector2(0, tile * 0.62), Vector2(tile, tile * 0.38)), _shade(WALL_FACE, lit, d))
					draw_rect(Rect2(o, Vector2(tile, 2)), _shade(WALL_TOP.lightened(0.15), lit, d))
				Level.CORRIDOR:
					draw_rect(r.grow(-1), _shade(CORR, lit, d))
					draw_circle(c, tile * 0.05, _shade(FLOOR_DOT, lit, d))
				_:
					draw_rect(r.grow(-1), _shade(FLOOR, lit, d))
					if t == Level.FLOOR:
						draw_circle(c, tile * 0.05, _shade(FLOOR_DOT, lit, d))
			match t:
				Level.DOOR:
					draw_rect(Rect2(o + Vector2(tile * 0.14, tile * 0.1), Vector2(tile * 0.72, tile * 0.8)), _shade(DOOR.darkened(0.35), lit, d))
					glyph(c, "+", _shade(DOOR.lightened(0.2), lit, d), gsize)
				Level.OPEN_DOOR:
					glyph(c, "'", _shade(DOOR, lit, d), gsize)
				Level.STAIRS:
					if lit:
						draw_circle(c, tile * 0.44, Color(ACCENT, 0.16))
					glyph(c, ">", _shade(ACCENT, lit, d), gsize + 6)
				Level.UPSTAIRS:
					glyph(c, "<", _shade(Color("#8d86a3"), lit, d), gsize)
			if lv.traps.has(i) and lv.traps[i].f:
				glyph(c, "^", _shade(Color("#ff5d7a"), lit, d), gsize)
	# Items (remembered ones too).
	for e in lv.items:
		if not e.s or e.x < x0 or e.x > x1 or e.y < y0 or e.y > y1:
			continue
		var lit2 := run.fov[Level.idx(e.x, e.y)] == 1
		var c2 := cell_origin(Vector2(e.x, e.y)) + Vector2(tile, tile) * 0.5
		var col := run.item_color(e.it)
		if e.it.id == "amulet":
			draw_circle(c2, tile * 0.46, Color(ACCENT, 0.25 + 0.1 * sin(Time.get_ticks_msec() / 200.0)))
			queue_redraw()
		glyph(c2, Run.item_glyph(e.it), _shade(col, lit2, me.distance_to(Vector2(e.x, e.y))), gsize)
	# Monsters.
	for m in lv.monsters:
		if not run.can_see(m):
			continue
		var mc := cell_origin(Vector2(m.x, m.y)) + Vector2(tile, tile) * 0.5
		var md: Dictionary = Defs.mon(m.t)
		var col2 := Color(md.c)
		var fl: bool = flashes.has(m.id)
		var boss: bool = md.ai == "boss"
		draw_circle(mc, tile * (0.47 if boss else 0.42), Color("#ff3b30", 0.55) if fl else Color(col2.darkened(0.78), 0.92))
		draw_arc(mc, tile * (0.47 if boss else 0.42), 0, TAU, 28, Color(col2, 0.7 if not boss else 1.0), 3.0 if boss else 2.0, true)
		glyph(mc, md.g, Color.WHITE if fl else col2, gsize + (6 if boss else 0))
		if int(m.sl) > 0 or not m.aw:
			glyph(mc + Vector2(tile * 0.32, -tile * 0.3), "z", Color("#9fd0ff"), int(tile * 0.3))
		if int(m.hp) < int(m.mhp):
			var w := tile * 0.7
			var bp := mc + Vector2(-w * 0.5, tile * 0.4)
			draw_rect(Rect2(bp, Vector2(w, 5)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(bp, Vector2(w * clampf(float(m.hp) / float(m.mhp), 0, 1), 5)), Color("#ff6b5e"))
	# Player.
	var pc := cell_origin(me) + Vector2(tile, tile) * 0.5
	draw_circle(pc, tile * 0.44, Color(ACCENT.darkened(0.7), 0.95))
	draw_arc(pc, tile * 0.44, 0, TAU, 32, ACCENT, 3.0, true)
	glyph(pc, "@", PLAYER, gsize + 2)
	# Effects.
	for b in bolts:
		var a := cell_origin(Vector2(b.a)) + Vector2(tile, tile) * 0.5
		var z := cell_origin(Vector2(b.b)) + Vector2(tile, tile) * 0.5
		var k: float = 1.0 - b.t / 0.28
		draw_line(a, z, Color(b.c, k), 8.0 if b.z else 4.0, true)
		draw_circle(z, tile * 0.18 * k + 2, Color(b.c, k))
	for b in bursts:
		var bc := cell_origin(Vector2(b.p)) + Vector2(tile, tile) * 0.5
		var kk: float = b.t / 0.45
		draw_arc(bc, tile * (0.3 + kk * 1.2), 0, TAU, 32, Color(b.c, 1.0 - kk), 4.0, true)
	for f in floaters:
		var fp := cell_origin(f.p) + Vector2(tile * 0.5, tile * 0.2 - f.t * tile * 0.9)
		var fc: Color = f.c
		var fs := int(tile * 0.46)
		var txt: String = f.s
		draw_string_outline(font, fp + Vector2(-tile, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, tile * 2, fs, 6, Color(0, 0, 0, 1.0 - f.t))
		draw_string(font, fp + Vector2(-tile, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, tile * 2, fs, Color(fc, 1.0 - f.t / 0.9))
	if aiming:
		draw_rect(Rect2(Vector2.ZERO, size), Color(ACCENT, 0.9), false, 6.0)
