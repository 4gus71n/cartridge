class_name PanZoomView
extends Control
## Base for the photo and map panels: one-finger / mouse drag pans,
## two-finger pinch zooms (with pan), mouse wheel / trackpad zooms at the
## cursor, a short touch without movement is a tap. Content is drawn at
## `content * zoom + offset` (screen = local control coordinates).

signal tapped(pos: Vector2)
signal double_tapped(pos: Vector2)
signal view_changed

const TAP_SLOP := 14.0
const DOUBLE_TAP_MS := 320

var content_size := Vector2(1, 1)
var zoom := 1.0
var offset := Vector2.ZERO
var max_zoom_factor := 4.0   # max zoom relative to "fit"
var interactive := true

var _touches := {}           # index -> position
var _tap_start := Vector2.ZERO
var _tap_time := 0
var _tap_valid := false
var _last_tap_time := -10000
var _last_tap_pos := Vector2.ZERO
var _mouse_down := false
var _tween: Tween


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)


func fit_zoom() -> float:
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return minf(size.x / content_size.x, size.y / content_size.y)


func min_zoom() -> float:
	return fit_zoom()


func max_zoom() -> float:
	return fit_zoom() * max_zoom_factor


func reset_view() -> void:
	zoom = fit_zoom()
	offset = (size - content_size * zoom) / 2.0
	_apply()


var _last_size := Vector2.ZERO


func _on_resized() -> void:
	# Keep the same content point at the centre when the panel changes size.
	if _last_size.x < 1.0 or _last_size.y < 1.0:
		_last_size = size
		reset_view()
		return
	var centre := (_last_size / 2.0 - offset) / zoom
	_last_size = size
	zoom = clampf(zoom, min_zoom(), max_zoom())
	offset = size / 2.0 - centre * zoom
	_apply()


func screen_to_content(p: Vector2) -> Vector2:
	return (p - offset) / zoom


func content_to_screen(p: Vector2) -> Vector2:
	return p * zoom + offset


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var target := clampf(zoom * factor, min_zoom(), max_zoom())
	var anchor := screen_to_content(screen_pos)
	zoom = target
	offset = screen_pos - anchor * zoom
	_apply()


func pan_by(delta: Vector2) -> void:
	offset += delta
	_apply()


## Smoothly frame a content-space rect (with padding) — used on reveal.
func animate_to_rect(r: Rect2, pad: float = 60.0, duration: float = 0.7) -> void:
	var avail := size - Vector2(pad, pad) * 2.0
	var z := minf(avail.x / maxf(r.size.x, 1.0), avail.y / maxf(r.size.y, 1.0))
	z = clampf(z, min_zoom(), max_zoom())
	var target_off := size / 2.0 - r.get_center() * z
	animate_to(z, target_off, duration)


func animate_to(z: float, off: Vector2, duration: float = 0.6) -> void:
	if _tween:
		_tween.kill()
	var z0 := zoom
	# Interpolate in "content centre" space so the motion looks straight.
	var c0 := screen_to_content(size / 2.0)
	var c1 := (size / 2.0 - off) / z
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(t: float) -> void:
		zoom = exp(lerpf(log(z0), log(z), t))
		var c := c0.lerp(c1, t)
		offset = size / 2.0 - c * zoom
		_apply(), 0.0, 1.0, duration)


func _clamp() -> void:
	var scaled := content_size * zoom
	for axis in 2:
		if scaled[axis] <= size[axis]:
			offset[axis] = (size[axis] - scaled[axis]) / 2.0
		else:
			offset[axis] = clampf(offset[axis], size[axis] - scaled[axis], 0.0)


func _apply() -> void:
	_clamp()
	_view_updated()
	view_changed.emit()


## Override: push zoom/offset to children or redraw.
func _view_updated() -> void:
	queue_redraw()


# --- input ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
		accept_event()
	elif event is InputEventScreenDrag:
		_on_drag(event)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _mouse_down:
			pan_by(event.relative)
			if event.position.distance_to(_tap_start) > TAP_SLOP:
				_tap_valid = false
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		pan_by(-event.delta * 12.0)
		accept_event()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		_kill_tween()
		if _touches.size() == 1:
			_begin_tap(e.position)
		else:
			_tap_valid = false
	else:
		_touches.erase(e.index)
		if _touches.is_empty():
			_end_tap(e.position)


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		_touches[e.index] = e.position
		return
	if _touches.size() == 1:
		_touches[e.index] = e.position
		if e.position.distance_to(_tap_start) > TAP_SLOP:
			_tap_valid = false
		if not _tap_valid:
			pan_by(e.relative)
		return
	# Two (or more) fingers: pinch around the midpoint of the first two.
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var old_mid := (a + b) / 2.0
	var old_dist := a.distance_to(b)
	_touches[e.index] = e.position
	a = _touches[keys[0]]
	b = _touches[keys[1]]
	var mid := (a + b) / 2.0
	var dist := a.distance_to(b)
	if old_dist > 4.0 and dist > 4.0:
		zoom_at(old_mid, dist / old_dist)
	pan_by(mid - old_mid)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		_kill_tween()
		zoom_at(e.position, 1.15 if e.factor == 0 else 1.0 + 0.15 * e.factor)
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		_kill_tween()
		zoom_at(e.position, 1.0 / (1.15 if e.factor == 0 else 1.0 + 0.15 * e.factor))
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_mouse_down = true
			_kill_tween()
			_begin_tap(e.position)
		else:
			_mouse_down = false
			_end_tap(e.position)


func _begin_tap(p: Vector2) -> void:
	_tap_start = p
	_tap_time = Time.get_ticks_msec()
	_tap_valid = true


func _end_tap(p: Vector2) -> void:
	if not _tap_valid:
		return
	_tap_valid = false
	var now := Time.get_ticks_msec()
	# Judge by distance only: slow WebViews deliver touch-up events late, so a
	# duration limit would drop genuine taps there.
	if p.distance_to(_tap_start) > TAP_SLOP:
		return
	if now - _last_tap_time < DOUBLE_TAP_MS and p.distance_to(_last_tap_pos) < 60.0:
		_last_tap_time = -10000
		double_tapped.emit(p)
		return
	_last_tap_time = now
	_last_tap_pos = p
	tapped.emit(p)


func _kill_tween() -> void:
	if _tween:
		_tween.kill()
		_tween = null
