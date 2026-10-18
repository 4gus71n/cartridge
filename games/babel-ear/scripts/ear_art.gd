class_name EarArt
extends Control
## Menu key art: concentric sound ripples around a glowing "ear" swirl, with
## greetings in many languages drifting around it. Latin/Greek/Cyrillic only
## (Godot's default font has no CJK/Arabic/Hebrew glyphs).

const WORDS := ["Hola", "Bonjour", "Привет", "Ciao", "Hallo", "Γειά σου", "Olá", "Cześć",
	"Hej", "Szia", "Salve", "Moi", "Kumusta", "Привіт"]

var accent := Color("#38d9c0")
var accent2 := Color("#8f7bff")
var _t := 0.0
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = get_theme_default_font()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	# ripples
	for k in 4:
		var ph := fmod(_t * 0.25 + k * 0.25, 1.0)
		var rr := r * (0.36 + ph * 0.5)
		draw_arc(c, rr, 0, TAU, 96, Color(accent, 0.35 * (1.0 - ph)), 3.0, true)
	# greetings on two staggered ellipses, slowly orbiting
	var n := WORDS.size()
	for i in n:
		var a := TAU * i / n + _t * 0.05
		var outer := i % 2 == 0
		var rx := size.x * (0.41 if outer else 0.27)
		var ry := size.y * (0.42 if outer else 0.30)
		var p := c + Vector2(cos(a) * rx, sin(a) * ry)
		var fs := 30 if outer else 24
		var col := Color(accent if outer else accent2, 0.42 + 0.3 * (0.5 + 0.5 * sin(_t * 0.8 + i)))
		var w := _font.get_string_size(WORDS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, p - Vector2(w * 0.5, -fs * 0.35), WORDS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# central disc + ear swirl + sound bars
	draw_circle(c, r * 0.36, Color("#14122e"))
	draw_arc(c, r * 0.36, 0, TAU, 96, Color(accent, 0.9), 4.0, true)
	var bars := 9
	for i in bars:
		var x := c.x + (i - (bars - 1) * 0.5) * r * 0.075
		var h := r * (0.12 + 0.2 * absf(sin(_t * 2.2 + i * 0.9)) * (1.0 - absf(i - 4) / 6.0))
		var col := accent.lerp(accent2, i / float(bars - 1))
		draw_line(Vector2(x, c.y - h), Vector2(x, c.y + h), col, r * 0.04, true)
