class_name WaveformView
extends Control
## Mirrored bar waveform of the current clip (peaks precomputed in the
## manifest). Bars left of `progress` glow in the accent colour; while
## `playing`, bars near the play head bounce a little.

var peaks: Array = []:
	set(v):
		peaks = v
		queue_redraw()
var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
var playing := false
var accent := Color("#38d9c0")
var idle := Color(1, 1, 1, 0.22)
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if playing or progress > 0.0:
		queue_redraw()


func _draw() -> void:
	var n := peaks.size()
	if n == 0:
		n = 48
	var w := size.x
	var h := size.y
	var slot := w / float(n)
	var bar := maxf(3.0, slot * 0.58)
	var mid := h * 0.5
	for i in n:
		var p: float = float(peaks[i]) if i < peaks.size() else 0.25 + 0.2 * sin(i * 0.7)
		var frac := (i + 0.5) / float(n)
		var lit := frac <= progress
		var amp := 0.08 + 0.92 * pow(clampf(p, 0.0, 1.0), 0.8)
		if playing and absf(frac - progress) < 0.08:
			amp *= 1.0 + 0.18 * sin(_t * 22.0 + i)
		var bh := maxf(bar, amp * h * 0.92)
		var x := i * slot + (slot - bar) * 0.5
		var col := accent if lit else idle
		if lit and absf(frac - progress) < 0.03 and playing:
			col = accent.lightened(0.35)
		draw_rect(Rect2(x, mid - bh * 0.5 + bar * 0.5, bar, bh - bar), col)
		draw_circle(Vector2(x + bar * 0.5, mid - bh * 0.5 + bar * 0.5), bar * 0.5, col)
		draw_circle(Vector2(x + bar * 0.5, mid + bh * 0.5 - bar * 0.5), bar * 0.5, col)
