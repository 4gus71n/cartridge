class_name SignTile
extends Control
## Tappable sign thumbnail for the Learn grid. Passes drags through so the
## parent ScrollContainer can scroll; a short tap emits `tapped`.

signal tapped(id: String)

const TAP_SLOP := 24.0

var sign_id := ""
var marked := false
var _view: SignView
var _press := Vector2.INF


func _init(id := "") -> void:
	sign_id = id


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_view = SignView.new()
	_view.shadow = false
	_view.fill_ratio = 0.84
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_view.sign_id = sign_id


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05) if not marked else Color("#ff4d5a", 0.18)
	sb.set_corner_radius_all(18)
	sb.anti_aliasing = true
	if marked:
		sb.border_color = Color("#ff4d5a", 0.7)
		sb.set_border_width_all(2)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.position
		elif _press != Vector2.INF:
			if event.position.distance_to(_press) < TAP_SLOP:
				tapped.emit(sign_id)
			_press = Vector2.INF
	elif event is InputEventMouseMotion and _press != Vector2.INF:
		if event.position.distance_to(_press) >= TAP_SLOP:
			_press = Vector2.INF
