class_name PlotView
extends Control
## The plot: grid + labelled axes, targets, asteroids, walls, live preview
## curve, the ideal curve, and the rocket flight animation (trail, target
## pops, explosion, win burst). Pure drawing — the flight itself is computed
## up front by Flight.simulate and only replayed here.

signal flight_finished(res: Dictionary)
signal target_hit(index: int)

const BG_COL := Color("#0f1528")
const GRID_MINOR := Color(1, 1, 1, 0.045)
const GRID_MAJOR := Color(1, 1, 1, 0.09)
const AXIS_COL := Color("#7d87a3")
const LABEL_COL := Color("#8a93ad")
const TARGET_COL := Color("#ffd166")
const HIT_COL := Color("#69db7c")
const ROCK_COL := Color("#5d5068")
const ROCK_EDGE := Color("#8d7d9a")
const WALL_COL := Color("#ff4d6d")
const PREVIEW_COL := Color("#4cc9f0")
const IDEAL_COL := Color("#ffd166")
const GHOST_COL := Color("#ff8fa3")
const TRAIL_COL := Color("#ffc46b")
const SPEED := 8.0          ## world x-units per second (a full flight ≈ 2.5 s)
const END_DELAY := 0.75     ## seconds between landing/crash and flight_finished

var level: Dictionary = {}
var preview: MathExpr = null        ## live curve (easy levels)
var ideal: MathExpr = null          ## dashed gold curve shown after solving
var ghost := PackedVector2Array()   ## path of the last failed launch
var demo_expr: MathExpr = null      ## menu mode: replays this flight forever

var _res: Dictionary = {}
var _flying := false
var _x := Flight.X_MIN
var _end_timer := -1.0
var _hit_time := {}
var _particles: Array = []
var _rock_shapes: Array = []
var _bg_stars: Array = []
var _time := 0.0
var _shake := 0.0
var _landed := false
var _frozen := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		_bg_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.6, 1.8), rng.randf_range(0.15, 0.6)])


func set_level(lvl: Dictionary) -> void:
	level = lvl
	_res = {}
	_flying = false
	_landed = false
	_hit_time.clear()
	_particles.clear()
	ghost = PackedVector2Array()
	ideal = null
	preview = null
	_rock_shapes.clear()
	var rocks: Array = lvl.get("rocks", [])
	for r in rocks.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + r * 37 + int(rocks[r][0] * 10)
		var pts := PackedVector2Array()
		var n := 11
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.15, 0.15)
			pts.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.82, 1.0))
		var craters := []
		for c in 3:
			craters.append([Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)),
				rng.randf_range(0.12, 0.24)])
		_rock_shapes.append([pts, craters, rng.randf() * TAU])
	queue_redraw()


func is_flying() -> bool:
	return _flying or _end_timer >= 0.0


## Starts replaying a simulated flight.
func launch(res: Dictionary) -> void:
	_res = res
	_flying = true
	_frozen = false
	_landed = false
	_x = Flight.X_MIN
	_end_timer = -1.0
	_hit_time.clear()
	ghost = PackedVector2Array()
	queue_redraw()


## Drops the replayed flight (its path lives on as `ghost`).
func clear_flight() -> void:
	_res = {}
	_landed = false
	_frozen = false
	queue_redraw()


## Jumps to the end of the current flight and emits flight_finished now
## (tests, and the poster capture).
func finish_now() -> void:
	if _res.is_empty():
		return
	_x = Flight.X_MAX + 1.0
	_step_flight(0.0)
	_end_timer = -1.0
	_flying = false
	flight_finished.emit(_res)


## Freezes the flight at world x (poster capture).
func freeze_at(x: float) -> void:
	_x = x
	_step_flight(0.0)
	_flying = false
	_frozen = true
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta * 2.5)
	if _frozen:
		pass
	elif _flying:
		_x += SPEED * delta
		_step_flight(delta)
	elif _end_timer >= 0.0:
		_end_timer -= delta
		if _end_timer < 0.0:
			_end_timer = -1.0
			flight_finished.emit(_res)
	elif demo_expr != null:
		launch(Flight.simulate(demo_expr, level))
	_update_particles(delta)
	queue_redraw()


func _point_count() -> int:
	return (_res.points as PackedVector2Array).size() if not _res.is_empty() else 0


## Fractional index of the rocket along the sampled path.
func _index() -> float:
	return (_x - Flight.X_MIN) / Flight.DX


func _step_flight(_delta: float) -> void:
	var pts: PackedVector2Array = _res.points
	var idx := _index()
	var hit: PackedInt32Array = _res.hit_at
	for t in hit.size():
		if hit[t] >= 0 and idx >= hit[t] and not _hit_time.has(t):
			_hit_time[t] = _time
			var tp: Array = level.targets[t]
			_burst(w2s(Vector2(tp[0], tp[1])), HIT_COL if t < hit.size() - 1 else TARGET_COL, 16, 160.0)
			target_hit.emit(t)
	if idx >= pts.size() - 1:
		if not _flying:
			return
		_flying = false
		_landed = true
		_end_timer = END_DELAY
		if _res.crash != Flight.Crash.NONE:
			_explode(w2s(_res.crash_point))
		elif _res.success:
			_win_burst()


# --- coordinates -------------------------------------------------------

func _unit() -> float:
	return size.x / (Flight.X_MAX - Flight.X_MIN)


func w2s(p: Vector2) -> Vector2:
	var u := _unit()
	return Vector2((p.x - Flight.X_MIN) * u, (Flight.Y_MAX - clampf(p.y, -40.0, 40.0)) * size.y
		/ (Flight.Y_MAX - Flight.Y_MIN))


func _rocket_state() -> Array:
	var pts: PackedVector2Array = _res.points
	var idx := clampf(_index(), 0.0, pts.size() - 1.0)
	var i0 := int(floor(idx))
	var i1 := mini(i0 + 1, pts.size() - 1)
	var p := pts[i0].lerp(pts[i1], idx - i0)
	var a := pts[maxi(i0 - 2, 0)]
	var b := pts[mini(i0 + 3, pts.size() - 1)]
	var dir := w2s(b) - w2s(a)
	return [p, dir.angle() if dir.length() > 0.01 else 0.0, i0]


# --- drawing -----------------------------------------------------------

func _draw() -> void:
	var off := Vector2.ZERO
	if _shake > 0.0:
		off = Vector2(sin(_time * 70.0), cos(_time * 53.0)) * _shake * 9.0
	draw_set_transform(off)
	draw_rect(Rect2(-off, size), BG_COL)
	for s in _bg_stars:
		draw_circle(s[0] * size, s[1], Color(1, 1, 1, s[2] * (0.75 + 0.25 * sin(_time * 1.3 + s[1] * 9.0))))
	_draw_grid()
	if level.is_empty():
		return
	_draw_walls()
	_draw_rocks()
	if ideal != null:
		_draw_curve(ideal, IDEAL_COL, 3.0, true)
	if preview != null and not _flying:
		_draw_curve(preview, Color(PREVIEW_COL, 0.75), 3.0, false)
	if ghost.size() > 1:
		_draw_path(ghost, Color(GHOST_COL, 0.45), 2.5)
	_draw_targets()
	if not _res.is_empty() and _point_count() > 0:
		_draw_trail()
		if _flying or _frozen:
			_draw_rocket()
	_draw_particles()
	draw_set_transform(Vector2.ZERO)


func _draw_grid() -> void:
	var u := _unit()
	var font := get_theme_default_font()
	var fs := int(clampf(u * 0.62, 13, 24))
	for k in range(-10, 11):
		var col := GRID_MAJOR if k % 2 == 0 else GRID_MINOR
		var sx := w2s(Vector2(k, 0)).x
		var sy := w2s(Vector2(0, k)).y
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), col, 1.0)
		draw_line(Vector2(0, sy), Vector2(size.x, sy), col, 1.0)
	var o := w2s(Vector2.ZERO)
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), AXIS_COL, 2.0, true)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), AXIS_COL, 2.0, true)
	# Arrow heads + axis names.
	draw_colored_polygon(PackedVector2Array([Vector2(size.x, o.y), Vector2(size.x - 12, o.y - 6),
		Vector2(size.x - 12, o.y + 6)]), AXIS_COL)
	draw_colored_polygon(PackedVector2Array([Vector2(o.x, 0), Vector2(o.x - 6, 12), Vector2(o.x + 6, 12)]),
		AXIS_COL)
	draw_string(font, Vector2(size.x - fs * 1.1, o.y - 10), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2,
		AXIS_COL)
	draw_string(font, Vector2(o.x + 12, fs + 4), "y", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2, AXIS_COL)
	for k in range(-10, 11):
		if k == 0:
			continue
		var tick := 5.0 if k % 2 else 8.0
		var sx := w2s(Vector2(k, 0)).x
		var sy := w2s(Vector2(0, k)).y
		draw_line(Vector2(sx, o.y - tick), Vector2(sx, o.y + tick), AXIS_COL, 2.0)
		draw_line(Vector2(o.x - tick, sy), Vector2(o.x + tick, sy), AXIS_COL, 2.0)
		if k % 2 != 0 or absi(k) == 10:
			continue
		var t := Forms.num_signed(k)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(sx - tw / 2.0, o.y + fs + 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL_COL)
		draw_string(font, Vector2(o.x - tw - 12, sy + fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL_COL)
	draw_string(font, Vector2(o.x - fs * 0.8, o.y + fs + 6), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL_COL)


func _draw_walls() -> void:
	for w in level.get("walls", []):
		var r := Flight.wall_rect(w)
		var a := w2s(Vector2(r.position.x, r.end.y))
		var b := w2s(Vector2(r.end.x, r.position.y))
		var sr := Rect2(a, b - a)
		draw_rect(sr, Color(WALL_COL, 0.22))
		var y := sr.position.y + 7.0
		while y < sr.end.y:
			draw_line(Vector2(sr.position.x, y), Vector2(sr.end.x, y), Color(WALL_COL, 0.18), 2.0)
			y += 14.0
		var glow := 0.75 + 0.25 * sin(_time * 4.0)
		draw_rect(sr, Color(WALL_COL, glow), false, 3.0)


func _draw_rocks() -> void:
	var u := _unit()
	var rocks: Array = level.get("rocks", [])
	for i in rocks.size():
		var c := w2s(Vector2(rocks[i][0], rocks[i][1]))
		var rad: float = rocks[i][2] * u
		var shape: Array = _rock_shapes[i]
		var rot: float = shape[2] + _time * 0.15 * (1.0 if i % 2 == 0 else -1.0)
		var pts := PackedVector2Array()
		for p in shape[0]:
			pts.append(c + (p as Vector2).rotated(rot) * rad)
		draw_colored_polygon(pts, ROCK_COL)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, ROCK_EDGE, 2.5, true)
		for cr in shape[1]:
			draw_circle(c + (cr[0] as Vector2).rotated(rot) * rad, cr[1] * rad, ROCK_COL.darkened(0.3))
		# Danger halo = the real collision radius.
		draw_arc(c, rad + Flight.ROCKET_R * u, 0, TAU, 40, Color(WALL_COL, 0.18), 1.5, true)


func _draw_targets() -> void:
	var u := _unit()
	var targets: Array = level.targets
	for t in targets.size():
		var c := w2s(Vector2(targets[t][0], targets[t][1]))
		var rad := Flight.TARGET_R * u
		var hit := _hit_time.has(t)
		var col := HIT_COL if hit else TARGET_COL
		var pulse := 1.0 + 0.06 * sin(_time * 3.0 + t)
		if hit:
			var age: float = _time - _hit_time[t]
			if age < 0.6:
				draw_arc(c, rad * (1.0 + age * 2.5), 0, TAU, 40, Color(col, 0.8 * (1.0 - age / 0.6)), 3.0, true)
			pulse = 1.0
		if t == targets.size() - 1:
			draw_colored_polygon(star_points(c, rad * 1.15 * pulse, rad * 0.5 * pulse, -PI / 2), Color(col, 0.95))
			if not hit:
				draw_circle(c, rad * 1.5, Color(col, 0.08))
		else:
			draw_circle(c, rad * pulse, Color(col, 0.13))
			draw_arc(c, rad * pulse, 0, TAU, 40, col, 4.0, true)
			draw_arc(c, rad * 0.45, 0, TAU, 24, Color(col, 0.6), 2.0, true)


## Plots f across the plot, breaking where it is undefined or jumps.
func _draw_curve(f: MathExpr, col: Color, width: float, dashed: bool) -> void:
	var run := PackedVector2Array()
	var n := 320
	var prev_y := NAN
	var dash := 0
	for k in n + 1:
		var x := Flight.X_MIN + (Flight.X_MAX - Flight.X_MIN) * k / n
		var y := f.eval(x)
		var broken := not is_finite(y) or (is_finite(prev_y) and absf(y - prev_y) > 25.0 and
			(absf(y) < 30 or absf(prev_y) < 30))
		if broken:
			_flush(run, col, width, dashed)
			run = PackedVector2Array()
		if is_finite(y):
			run.append(w2s(Vector2(x, y)))
		prev_y = y
		dash += 1
	_flush(run, col, width, dashed)


func _flush(run: PackedVector2Array, col: Color, width: float, dashed: bool) -> void:
	if run.size() < 2:
		return
	if not dashed:
		draw_polyline(run, col, width, true)
		return
	# Dashes by screen length.
	var on := true
	var acc := 0.0
	var seg := PackedVector2Array([run[0]])
	for i in range(1, run.size()):
		acc += run[i].distance_to(run[i - 1])
		seg.append(run[i])
		if acc >= (14.0 if on else 9.0):
			if on and seg.size() > 1:
				draw_polyline(seg, col, width, true)
			on = not on
			acc = 0.0
			seg = PackedVector2Array([run[i]])
	if on and seg.size() > 1:
		draw_polyline(seg, col, width, true)


func _draw_path(pts: PackedVector2Array, col: Color, width: float) -> void:
	var s := PackedVector2Array()
	for p in pts:
		s.append(w2s(p))
	draw_polyline(s, col, width, true)


func _draw_trail() -> void:
	var pts: PackedVector2Array = _res.points
	var last := clampi(int(floor(_index())), 0, pts.size() - 1)
	if last < 1:
		return
	var s := PackedVector2Array()
	for i in range(0, last + 1, 2):
		s.append(w2s(pts[i]))
	if _flying or _landed:
		var st := _rocket_state()
		s.append(w2s(st[0]))
	if s.size() < 2:
		return
	var crashed: bool = _res.crash != Flight.Crash.NONE and _landed
	var base := GHOST_COL if crashed else TRAIL_COL
	draw_polyline(s, Color(base, 0.62), 4.0, true)
	# Bright fading tail right behind the rocket.
	var tail := mini(s.size(), 70)
	var tp := s.slice(s.size() - tail)
	var cols := PackedColorArray()
	for i in tail:
		var f := float(i) / maxf(1.0, tail - 1.0)
		cols.append(Color(base.lerp(Color("#fff3c4"), f), 0.15 + 0.85 * f))
	draw_polyline_colors(tp, cols, 7.0, true)


func _draw_rocket() -> void:
	var st := _rocket_state()
	var p := w2s(st[0])
	var ang: float = st[1]
	var sc := clampf(size.x / 440.0, 0.8, 2.0)
	var on_screen: bool = st[0].y <= Flight.Y_MAX and st[0].y >= Flight.Y_MIN
	if not on_screen:
		# Off the top/bottom: a chevron at the edge shows where it is.
		var up: bool = st[0].y > Flight.Y_MAX
		var ey := 14.0 if up else size.y - 14.0
		var d := -1.0 if up else 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(p.x, ey + d * 10), Vector2(p.x - 14, ey - d * 8),
			Vector2(p.x + 14, ey - d * 8)]), Color(TRAIL_COL, 0.9))
		return
	draw_set_transform(p, ang, Vector2(sc, sc))
	var fl := 10.0 + 6.0 * sin(_time * 40.0) + 3.0 * sin(_time * 23.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-14, -6), Vector2(-14 - fl - 8, 0), Vector2(-14, 6)]),
		Color("#ff7b39"))
	draw_colored_polygon(PackedVector2Array([Vector2(-14, -3.5), Vector2(-14 - fl * 0.6 - 3, 0),
		Vector2(-14, 3.5)]), Color("#ffe066"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -7), Vector2(-2, -7), Vector2(-16, -16),
		Vector2(-18, -16)]), Color("#ff4d6d"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, 7), Vector2(-2, 7), Vector2(-16, 16),
		Vector2(-18, 16)]), Color("#ff4d6d"))
	draw_colored_polygon(PackedVector2Array([Vector2(-15, -7), Vector2(8, -7), Vector2(8, 7),
		Vector2(-15, 7)]), Color("#eef1f8"))
	draw_colored_polygon(PackedVector2Array([Vector2(8, -7), Vector2(14, -5), Vector2(20, 0), Vector2(14, 5),
		Vector2(8, 7)]), Color("#ff4d6d"))
	draw_circle(Vector2(1, 0), 4.0, Color("#1b2440"))
	draw_circle(Vector2(1, 0), 2.6, Color("#4cc9f0"))
	draw_set_transform(Vector2.ZERO)
	# Exhaust sparks.
	if _flying and randf() < 0.6:
		var back := Vector2.from_angle(ang + PI)
		_particles.append({"p": p + back * 24.0 * sc, "v": back.rotated(randf_range(-0.5, 0.5)) * randf_range(40, 110),
			"life": 0.35, "max": 0.35, "col": Color("#ffb347"), "r": randf_range(1.5, 3.0)})


# --- particles -----------------------------------------------------------

func _burst(at: Vector2, col: Color, n: int, speed: float) -> void:
	for i in n:
		var a := randf() * TAU
		_particles.append({"p": at, "v": Vector2.from_angle(a) * randf_range(speed * 0.3, speed), "life": 0.7,
			"max": 0.7, "col": col, "r": randf_range(2.0, 4.0)})


func _explode(at: Vector2) -> void:
	_shake = 1.0
	for i in 46:
		var a := randf() * TAU
		var col: Color = [Color("#ffe066"), Color("#ff7b39"), Color("#ff4d6d"), Color("#c9c3d6")][i % 4]
		_particles.append({"p": at, "v": Vector2.from_angle(a) * randf_range(60, 330), "life": 0.9, "max": 0.9,
			"col": col, "r": randf_range(2.5, 6.0), "drag": 2.2})
	_particles.append({"p": at, "v": Vector2.ZERO, "life": 0.5, "max": 0.5, "col": Color("#ffe066"), "r": 0.0,
		"ring": 90.0})
	_particles.append({"p": at, "v": Vector2.ZERO, "life": 0.35, "max": 0.35, "col": Color(1, 1, 1, 0.9),
		"r": 28.0, "flash": true})


func _win_burst() -> void:
	var last: Array = level.targets[level.targets.size() - 1]
	var c := w2s(Vector2(last[0], last[1]))
	_particles.append({"p": c, "v": Vector2.ZERO, "life": 0.7, "max": 0.7, "col": TARGET_COL, "r": 0.0,
		"ring": 160.0})
	for i in 70:
		var col: Color = [Color("#ffd166"), Color("#69db7c"), Color("#4cc9f0"), Color("#ff8fa3"),
			Color("#b197fc")][i % 5]
		var origin := Vector2(randf() * size.x, -10.0) if i % 2 == 0 else c
		var v := Vector2(randf_range(-60, 60), randf_range(80, 220)) if i % 2 == 0 \
			else Vector2.from_angle(randf() * TAU) * randf_range(80, 300)
		_particles.append({"p": origin, "v": v, "life": 1.6, "max": 1.6, "col": col, "r": randf_range(3.0, 5.5),
			"confetti": true, "spin": randf() * TAU, "drag": 0.6})


func _update_particles(delta: float) -> void:
	var keep := []
	for q in _particles:
		q.life -= delta
		if q.life <= 0.0:
			continue
		q.p += q.v * delta
		q.v *= maxf(0.0, 1.0 - q.get("drag", 1.0) * delta)
		if q.get("confetti", false):
			q.v.y += 120.0 * delta
			q.spin += delta * 6.0
		keep.append(q)
	_particles = keep


func _draw_particles() -> void:
	for q in _particles:
		var f: float = q.life / q.max
		if q.has("ring"):
			draw_arc(q.p, q.ring * (1.0 - f) + 6.0, 0, TAU, 48, Color(q.col, f), 4.0, true)
		elif q.get("flash", false):
			draw_circle(q.p, q.r * (1.5 - f * 0.5), Color(q.col, f * 0.8))
		elif q.get("confetti", false):
			var d: Vector2 = Vector2.from_angle(q.spin) * q.r
			draw_line(q.p - d, q.p + d, Color(q.col, minf(1.0, f * 2.0)), 3.0)
		else:
			draw_circle(q.p, q.r * (0.4 + 0.6 * f), Color(q.col, f))


static func star_points(c: Vector2, r_out: float, r_in: float, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var r := r_out if k % 2 == 0 else r_in
		pts.append(c + Vector2.from_angle(rot + k * PI / 5) * r)
	return pts
