extends SceneTree
## Touch gestures -> actions: godot --headless --path . --script tests/gesture_check.gd
## Feeds synthetic mouse events (what touch emulation produces) to BoardView.

var _pass := 0
var _fail := 0
var _got: Array = []


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_run()


func _press(v: BoardView, p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	v._gui_input(e)


func _move(v: BoardView, p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	v._gui_input(e)


func _gesture(v: BoardView, a: Vector2, b: Vector2, steps := 8) -> Array:
	_got.clear()
	_press(v, a, true)
	for i in range(1, steps + 1):
		_move(v, a.lerp(b, float(i) / steps))
	_press(v, b, false)
	return _got.duplicate()


func _run() -> void:
	var v := BoardView.new()
	v.size = Vector2(672, 1100)
	root.add_child(v)
	var b := PrismBoard.new(9, 16, 1)
	b.start()
	v.set_board(b)
	v.action.connect(func(n: String) -> void: _got.append(n))
	await process_frame
	var c := v.cell_size()
	check(c >= 60.0, "cell size from layout (%.0f)" % c)
	var mid := v.size / 2.0

	check(_gesture(v, mid, mid, 0) == ["rotate"], "tap rotates")
	check(_gesture(v, mid, mid + Vector2(4, 3), 2) == ["rotate"], "jittery tap still rotates")
	var r := _gesture(v, mid, mid + Vector2(c * 3.2, 0))
	check(r.size() == 3 and r.all(func(x: String) -> bool: return x == "right"), "drag right 3 cells -> 3 x right %s" % [r])
	r = _gesture(v, mid, mid - Vector2(c * 2.1, 0))
	check(r.size() == 2 and r.all(func(x: String) -> bool: return x == "left"), "drag left 2 cells -> 2 x left %s" % [r])
	check(_gesture(v, mid, mid + Vector2(0, c * 4)) == ["hard"], "swipe down hard-drops")
	check(_gesture(v, mid, mid - Vector2(0, c * 3)) == ["hold"], "swipe up holds")
	check(_gesture(v, mid, mid + Vector2(0, c * 0.6)) == [], "tiny vertical drag does nothing")
	# Slow WebView: press and release arrive with no motion in between.
	check(_gesture(v, mid, mid + Vector2(0, c * 4), 0) == ["hard"], "burst swipe down (no motion events) hard-drops")
	r = _gesture(v, mid, mid + Vector2(c * 2.2, 0), 0)
	check(r == ["right", "right"], "burst drag right still moves %s" % [r])
	# Diagonal-ish swipes pick the dominant axis.
	check(_gesture(v, mid, mid + Vector2(c * 0.7, c * 3)) == ["hard"], "mostly-down swipe is a drop")
	print("gesture_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
