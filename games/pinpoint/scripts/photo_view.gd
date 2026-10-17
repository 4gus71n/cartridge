class_name PhotoView
extends PanZoomView
## Shows the round photo; pinch / wheel to zoom, drag to pan, double-tap
## toggles a 2.5x zoom at the tapped point.

const BG := Color("#070a12")

var texture: Texture2D


func _ready() -> void:
	super._ready()
	max_zoom_factor = 5.0
	double_tapped.connect(_on_double_tap)


func set_texture(t: Texture2D) -> void:
	texture = t
	content_size = t.get_size() if t else Vector2(4, 3)
	reset_view()


## Start covering the panel (crop); pinch out to see the whole photo.
func cover_zoom() -> float:
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return maxf(size.x / content_size.x, size.y / content_size.y)


func reset_view() -> void:
	zoom = cover_zoom()
	offset = (size - content_size * zoom) / 2.0
	_apply()


func _on_double_tap(p: Vector2) -> void:
	if zoom > cover_zoom() * 1.3:
		animate_to(cover_zoom(), (size - content_size * cover_zoom()) / 2.0, 0.3)
	else:
		var z := minf(cover_zoom() * 2.5, max_zoom())
		var anchor := screen_to_content(p)
		animate_to(z, size / 2.0 - anchor * z, 0.3)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if texture:
		draw_texture_rect(texture, Rect2(offset, content_size * zoom), false)
