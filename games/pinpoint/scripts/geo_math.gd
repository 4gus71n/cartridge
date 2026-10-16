class_name GeoMath
extends RefCounted
## Pure geo helpers: great-circle distance, scoring curve, unit formatting,
## geodesic interpolation. Geo points are Vector2(lon, lat) in degrees.

const EARTH_RADIUS_KM := 6371.0088
const KM_PER_MILE := 1.609344
const MAX_POINTS := 5000
const SCORE_SCALE_KM := 2000.0
const PERFECT_KM := 0.5
const COUNTRY_BONUS := 1000
const ROUND_MAX := MAX_POINTS + COUNTRY_BONUS


## Haversine great-circle distance in km.
static func distance_km(a: Vector2, b: Vector2) -> float:
	var lat1 := deg_to_rad(a.y)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := deg_to_rad(b.x - a.x)
	var h := sin(dlat / 2.0) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2.0) ** 2
	return 2.0 * EARTH_RADIUS_KM * asin(minf(1.0, sqrt(h)))


## Distance points: 5000 at the spot, ~1839 at 2000 km, ~0 at the antipode.
static func distance_points(km: float) -> int:
	if km <= PERFECT_KM:
		return MAX_POINTS
	return clampi(roundi(MAX_POINTS * exp(-km / SCORE_SCALE_KM)), 0, MAX_POINTS)


static func round_points(km: float, country_ok: bool) -> int:
	return distance_points(km) + (COUNTRY_BONUS if country_ok else 0)


## Locales that use miles for road distances.
static func locale_uses_miles(locale: String) -> bool:
	var parts := locale.replace("-", "_").split("_")
	if parts.size() < 2:
		return false
	return parts[1].to_upper() in ["US", "GB", "LR", "MM"]


static func format_distance(km: float, miles: bool) -> String:
	var v := km / KM_PER_MILE if miles else km
	var unit := "mi" if miles else "km"
	if v < 10.0:
		return "%.1f %s" % [v, unit]
	return "%s %s" % [group_digits(roundi(v)), unit]


## 12345 -> "12,345" (thin, locale-neutral separator).
static func group_digits(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Points along the great circle from a to b (inclusive), `steps` segments.
static func geodesic(a: Vector2, b: Vector2, steps: int = 64) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p1 := _to_vec(a)
	var p2 := _to_vec(b)
	var omega := acos(clampf(p1.dot(p2), -1.0, 1.0))
	if omega < 1e-6:
		out.append(a)
		out.append(b)
		return out
	var so := sin(omega)
	for i in steps + 1:
		var t := float(i) / steps
		var v := p1 * (sin((1.0 - t) * omega) / so) + p2 * (sin(t * omega) / so)
		out.append(_from_vec(v))
	return out


## Split a lon/lat polyline wherever it jumps across the antimeridian.
static func split_antimeridian(line: PackedVector2Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for i in line.size():
		var p := line[i]
		if i > 0 and absf(p.x - line[i - 1].x) > 180.0:
			var q := line[i - 1]
			# Interpolate the crossing latitude and close both halves at ±180.
			var edge := 180.0 if q.x > 0.0 else -180.0
			var px := p.x + (360.0 if edge > 0.0 else -360.0)
			var t := (edge - q.x) / (px - q.x) if px != q.x else 0.0
			var lat := lerpf(q.y, p.y, t)
			cur.append(Vector2(edge, lat))
			parts.append(cur)
			cur = PackedVector2Array()
			cur.append(Vector2(-edge, lat))
		cur.append(p)
	if cur.size() > 0:
		parts.append(cur)
	return parts


static func _to_vec(p: Vector2) -> Vector3:
	var lat := deg_to_rad(p.y)
	var lon := deg_to_rad(p.x)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))


static func _from_vec(v: Vector3) -> Vector2:
	v = v.normalized()
	return Vector2(rad_to_deg(atan2(v.y, v.x)), rad_to_deg(asin(clampf(v.z, -1.0, 1.0))))
