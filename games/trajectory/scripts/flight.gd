class_name Flight
extends RefCounted
## Pure flight simulation: the rocket follows y = f(x) from the left edge to
## the right edge of the plot. It must touch every target and must not touch
## any obstacle (circle asteroids, rectangular walls). Leaving the visible
## plot vertically is allowed (only the visible part has anything to hit).

const X_MIN := -10.0
const X_MAX := 10.0
const Y_MIN := -10.0
const Y_MAX := 10.0
const DX := 0.02            ## sampling step (1000 segments across the plot)
const TARGET_R := 0.6       ## how close the path must pass to a target centre
const ROCKET_R := 0.15      ## rocket "size" used against obstacles

enum Crash { NONE, ROCK, WALL, UNDEFINED }


## Samples the curve. Returns:
##   points: PackedVector2Array (world coords, up to the crash point)
##   hit_at: PackedInt32Array, per target the segment index where it was hit (-1 = missed)
##   crash: Crash, crash_index: obstacle index, crash_point: Vector2
##   success: bool (no crash and every target hit)
static func simulate(f: MathExpr, level: Dictionary) -> Dictionary:
	var targets: Array = level.get("targets", [])
	var rocks: Array = level.get("rocks", [])
	var walls: Array = level.get("walls", [])
	var hit_at := PackedInt32Array()
	hit_at.resize(targets.size())
	hit_at.fill(-1)
	var points := PackedVector2Array()
	var res := {"points": points, "hit_at": hit_at, "crash": Crash.NONE, "crash_index": -1,
		"crash_point": Vector2.ZERO, "success": false}
	var steps := int(roundf((X_MAX - X_MIN) / DX))
	var prev := Vector2.ZERO
	for i in steps + 1:
		var x := X_MIN + i * DX
		var y := f.eval(x) if f != null else NAN
		if not is_finite(y) or absf(y) > 1e7:
			if absf(y) > 1e7 and is_finite(y):
				y = signf(y) * 1e7  # far off-screen: harmless, keep flying
			else:
				res.crash = Crash.UNDEFINED
				res.crash_point = Vector2(x, prev.y if i > 0 else 0.0)
				break
		var cur := Vector2(x, y)
		points.append(cur)
		if i == 0:
			prev = cur
			continue
		# Both ends above or below the plot: nothing to touch on this segment.
		var outside := (prev.y > Y_MAX + 2 and cur.y > Y_MAX + 2) or (prev.y < Y_MIN - 2 and cur.y < Y_MIN - 2)
		if not outside:
			var seg := i - 1
			for t in targets.size():
				if hit_at[t] < 0 and seg_point_dist(prev, cur, Vector2(targets[t][0], targets[t][1])) <= TARGET_R:
					hit_at[t] = seg
			for r in rocks.size():
				var c := Vector2(rocks[r][0], rocks[r][1])
				if seg_point_dist(prev, cur, c) <= float(rocks[r][2]) + ROCKET_R:
					res.crash = Crash.ROCK
					res.crash_index = r
					res.crash_point = closest_on_seg(prev, cur, c)
					break
			if res.crash == Crash.NONE:
				for w in walls.size():
					var rect := wall_rect(walls[w]).grow(ROCKET_R)
					var p = seg_rect_entry(prev, cur, rect)
					if p != null:
						res.crash = Crash.WALL
						res.crash_index = w
						res.crash_point = p
						break
			if res.crash != Crash.NONE:
				points[points.size() - 1] = res.crash_point
				break
		prev = cur
	res.points = points
	res.hit_at = hit_at
	res.success = res.crash == Crash.NONE and not hit_at.has(-1)
	return res


static func missed_count(res: Dictionary) -> int:
	return (res.hit_at as PackedInt32Array).count(-1)


static func wall_rect(w: Array) -> Rect2:
	var a := Vector2(minf(w[0], w[2]), minf(w[1], w[3]))
	var b := Vector2(maxf(w[0], w[2]), maxf(w[1], w[3]))
	return Rect2(a, b - a)


static func closest_on_seg(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 == 0.0:
		return a
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t


static func seg_point_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	return p.distance_to(closest_on_seg(a, b, p))


## First point where segment a->b enters `r` (Liang–Barsky), or null.
static func seg_rect_entry(a: Vector2, b: Vector2, r: Rect2):
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for k in 4:
		var p: float = ps[k]
		var q: float = qs[k]
		if p == 0.0:
			if q < 0.0:
				return null
		else:
			var t := q / p
			if p < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return null
	return a + d * t0
