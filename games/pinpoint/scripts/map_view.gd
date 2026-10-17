class_name MapView
extends PanZoomView
## World map panel. Land/borders/graticule are drawn once into a Node2D whose
## transform follows pan/zoom (no per-frame redraw); pins and lines are drawn
## in screen space on an overlay so they keep a constant size.

signal pin_dropped(geo: Vector2)

const OCEAN := Color("#0c1a2b")
const GRATICULE := Color(0.55, 0.7, 0.9, 0.10)
const EQUATOR := Color(0.55, 0.7, 0.9, 0.22)
const BORDER := Color(0.04, 0.08, 0.13, 0.9)
const LAND := ["#3d5e50", "#4f6146", "#5d5a45", "#41596a", "#5a4d5f", "#476357", "#5f5048"]
const GUESS := Color("#ff6b5b")
const TRUTH := Color("#3ddc97")
const LINE := Color(1, 1, 1, 0.92)

static var _world: WorldData
static var _land_mesh: ArrayMesh
static var _borders: PackedVector2Array

var guess := Vector2.ZERO
var has_guess := false
var truth := Vector2.ZERO
var has_truth := false
var line_t := 0.0                  # 0..1 progress of the reveal line
var pairs: Array[Dictionary] = []  # summary: {guess, truth}
var can_drop := true
var dots := PackedVector2Array()   # decorative geo points (menu hero)

var _land: Node2D
var _highlight: Node2D
var _overlay: Control
var _highlight_mesh: ArrayMesh


static func set_world(w: WorldData) -> void:
	_world = w
	var palette := PackedColorArray()
	for c in LAND:
		palette.append(Color(c))
	_land_mesh = w.build_land_mesh(palette).mesh
	_borders = w.border_segments()


func _ready() -> void:
	super._ready()
	content_size = MapProjection.map_size()
	max_zoom_factor = 40.0
	_land = _Layer.new()
	_land.draw_fn = _draw_land
	add_child(_land)
	_highlight = _Layer.new()
	_highlight.draw_fn = _draw_highlight
	add_child(_highlight)
	_overlay = _Overlay.new()
	_overlay.draw_fn = _draw_overlay
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	tapped.connect(_on_tap)
	double_tapped.connect(func(p: Vector2) -> void:
		var z := clampf(zoom * 2.0, min_zoom(), max_zoom())
		animate_to(z, p - screen_to_content(p) * z, 0.25))
	call_deferred("reset_view")


func _view_updated() -> void:
	if _land:
		_land.position = offset
		_land.scale = Vector2(zoom, zoom)
		_highlight.position = offset
		_highlight.scale = Vector2(zoom, zoom)
		_overlay.queue_redraw()
	queue_redraw()


func geo_to_screen(geo: Vector2) -> Vector2:
	return MapProjection.to_screen(geo, zoom, offset)


func screen_to_geo(p: Vector2) -> Vector2:
	return MapProjection.from_screen(p, zoom, offset)


func set_guess(geo: Vector2) -> void:
	guess = geo
	has_guess = true
	_overlay.queue_redraw()


func clear_marks() -> void:
	has_guess = false
	has_truth = false
	line_t = 0.0
	pairs.clear()
	_highlight_mesh = null
	_highlight.queue_redraw()
	_overlay.queue_redraw()


## Reveal: show truth pin, highlight its country, animate the line, frame both.
func reveal(truth_geo: Vector2, country_key: String) -> void:
	truth = truth_geo
	has_truth = true
	can_drop = false
	if _world and country_key != "":
		var c := PackedColorArray([Color(TRUTH, 0.35)])
		_highlight_mesh = _world.build_land_mesh(c, country_key).mesh
		_highlight.queue_redraw()
	frame_points([guess, truth])
	line_t = 0.0
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_method(func(t: float) -> void:
		line_t = t
		_overlay.queue_redraw(), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func show_pairs(list: Array[Dictionary]) -> void:
	pairs = list
	can_drop = false
	has_guess = false
	has_truth = false
	line_t = 1.0
	var pts: Array[Vector2] = []
	for p in list:
		pts.append(p.guess)
		pts.append(p.truth)
	if pts.size() > 0:
		frame_points(pts, 0.0)
	_overlay.queue_redraw()


func frame_points(points: Array[Vector2], duration: float = 0.7) -> void:
	if points.is_empty():
		return
	var r := Rect2(MapProjection.project(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(MapProjection.project(p))
	# Never zoom closer than ~25° across so the context stays readable.
	var min_span := 25.0 * MapProjection.UNITS_PER_DEG
	r = r.grow_individual(maxf(0, (min_span - r.size.x) / 2), maxf(0, (min_span * 0.7 - r.size.y) / 2),
		maxf(0, (min_span - r.size.x) / 2), maxf(0, (min_span * 0.7 - r.size.y) / 2))
	if duration <= 0.0:
		var avail := size - Vector2(140, 140)
		zoom = clampf(minf(avail.x / r.size.x, avail.y / r.size.y), min_zoom(), max_zoom())
		offset = size / 2.0 - r.get_center() * zoom
		_apply()
	else:
		animate_to_rect(r, 70.0, duration)


func zoom_step(factor: float) -> void:
	_kill_tween()
	zoom_at(size / 2.0, factor)


func _on_tap(p: Vector2) -> void:
	if not can_drop:
		return
	var geo := screen_to_geo(p)
	set_guess(geo)
	pin_dropped.emit(geo)


# --- drawing ------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OCEAN.darkened(0.35))


func _draw_land(ci: CanvasItem) -> void:
	var ms := MapProjection.map_size()
	ci.draw_rect(Rect2(Vector2.ZERO, ms), OCEAN)
	for lon in range(-180, 181, 30):
		var x := MapProjection.project(Vector2(lon, 0)).x
		ci.draw_line(Vector2(x, 0), Vector2(x, ms.y), GRATICULE, -1)
	for lat in range(-60, 61, 30):
		var y := MapProjection.project(Vector2(0, lat)).y
		ci.draw_line(Vector2(0, y), Vector2(ms.x, y), EQUATOR if lat == 0 else GRATICULE, -1)
	if _land_mesh:
		ci.draw_mesh(_land_mesh, null)
	if _borders.size() > 0:
		ci.draw_multiline(_borders, BORDER, -1)


func _draw_highlight(ci: CanvasItem) -> void:
	if _highlight_mesh:
		ci.draw_mesh(_highlight_mesh, null)


func _draw_overlay(ci: Control) -> void:
	for d in dots:
		var s := geo_to_screen(d)
		ci.draw_circle(s, 7.0, Color(GUESS, 0.22))
		ci.draw_circle(s, 3.2, GUESS)
	if pairs.size() > 0:
		for i in pairs.size():
			_draw_line_geo(ci, pairs[i].guess, pairs[i].truth, 1.0)
		for i in pairs.size():
			_draw_truth(ci, geo_to_screen(pairs[i].truth))
			_draw_pin(ci, geo_to_screen(pairs[i].guess), str(i + 1))
		return
	if has_guess and has_truth:
		_draw_line_geo(ci, guess, truth, line_t)
	if has_truth and line_t >= 0.98:
		_draw_truth(ci, geo_to_screen(truth))
	if has_guess:
		_draw_pin(ci, geo_to_screen(guess), "")


func _draw_line_geo(ci: Control, a: Vector2, b: Vector2, t: float) -> void:
	if t <= 0.0:
		return
	var pts := GeoMath.geodesic(a, b, 72)
	var n := maxi(2, int(ceil(pts.size() * t)))
	pts = pts.slice(0, n)
	for part in GeoMath.split_antimeridian(pts):
		if part.size() < 2:
			continue
		var scr := PackedVector2Array()
		for p in part:
			scr.append(geo_to_screen(p))
		# Dashes along the screen polyline.
		var dash := 14.0
		var gap := 9.0
		var acc := 0.0
		for i in scr.size() - 1:
			var s0 := scr[i]
			var s1 := scr[i + 1]
			var seg := s0.distance_to(s1)
			var pos := 0.0
			while pos < seg:
				var phase := fmod(acc + pos, dash + gap)
				var step := minf(seg - pos, (dash - phase) if phase < dash else (dash + gap - phase))
				if phase < dash:
					ci.draw_line(s0.lerp(s1, pos / seg), s0.lerp(s1, (pos + step) / seg), LINE, 4.0, true)
				pos += maxf(step, 0.5)
			acc += seg


func _draw_pin(ci: Control, p: Vector2, label: String) -> void:
	var head := p - Vector2(0, 34)
	ci.draw_colored_polygon(PackedVector2Array([p, head + Vector2(-12, 8), head + Vector2(12, 8)]), Color.WHITE)
	ci.draw_circle(head, 17.0, Color.WHITE)
	ci.draw_colored_polygon(PackedVector2Array([p - Vector2(0, 4), head + Vector2(-9, 9), head + Vector2(9, 9)]), GUESS)
	ci.draw_circle(head, 14.0, GUESS)
	if label == "":
		ci.draw_circle(head, 5.5, Color("#1b1b1b"))
	else:
		var font := ci.get_theme_default_font()
		var fs := 20
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, head + Vector2(-w / 2.0, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#1b1b1b"))
	ci.draw_circle(p, 3.0, Color(0, 0, 0, 0.5))


func _draw_truth(ci: Control, p: Vector2) -> void:
	ci.draw_circle(p, 15.0, Color(TRUTH, 0.25))
	ci.draw_circle(p, 10.0, Color.WHITE)
	ci.draw_circle(p, 7.5, TRUTH)


class _Layer extends Node2D:
	var draw_fn: Callable

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)


class _Overlay extends Control:
	var draw_fn: Callable

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)
