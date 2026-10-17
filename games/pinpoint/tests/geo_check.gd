extends SceneTree
## Pure math: great-circle distance, scoring curve, unit formatting,
## Miller projection round trip, geodesic + antimeridian split.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_distance()
	_scoring()
	_format()
	_projection()
	_geodesic()
	print("geo_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _distance() -> void:
	var paris := Vector2(2.3522, 48.8566)
	var london := Vector2(-0.1276, 51.5072)
	var d := GeoMath.distance_km(paris, london)
	check(near(d, 343.5, 2.0), "Paris-London ~343.5 km (%.1f)" % d)
	check(near(GeoMath.distance_km(london, paris), d, 1e-6), "distance is symmetric")
	check(GeoMath.distance_km(paris, paris) < 1e-6, "zero distance to self")
	var ny := Vector2(-74.006, 40.7128)
	var tokyo := Vector2(139.6503, 35.6762)
	check(near(GeoMath.distance_km(ny, tokyo), 10850.0, 30.0), "NYC-Tokyo ~10,850 km (%.0f)" % GeoMath.distance_km(ny, tokyo))
	var antipode := GeoMath.distance_km(Vector2(0, 0), Vector2(180, 0))
	check(near(antipode, PI * GeoMath.EARTH_RADIUS_KM, 0.5), "antipode = half circumference")
	check(near(GeoMath.distance_km(Vector2(0, 90), Vector2(123, -90)), PI * GeoMath.EARTH_RADIUS_KM, 0.5), "pole to pole")
	# Across the antimeridian is short, not ~360 degrees.
	check(GeoMath.distance_km(Vector2(179.5, 0), Vector2(-179.5, 0)) < 120.0, "antimeridian neighbours are close")


func _scoring() -> void:
	check(GeoMath.distance_points(0.0) == 5000, "perfect = 5000")
	check(GeoMath.distance_points(0.4) == 5000, "within 500 m = 5000")
	check(GeoMath.distance_points(2000.0) == roundi(5000 * exp(-1.0)), "2000 km = 5000/e (%d)" % GeoMath.distance_points(2000.0))
	check(GeoMath.distance_points(20015.0) <= 35, "antipode ~0 (%d)" % GeoMath.distance_points(20015.0))
	var prev := 6000
	var mono := true
	for km in [0.0, 1.0, 10.0, 100.0, 500.0, 1000.0, 3000.0, 8000.0, 15000.0, 20000.0]:
		var p := GeoMath.distance_points(km)
		if p > prev or p < 0 or p > 5000:
			mono = false
		prev = p
	check(mono, "points fall monotonically with distance and stay in 0..5000")
	check(GeoMath.round_points(100.0, true) == GeoMath.distance_points(100.0) + GeoMath.COUNTRY_BONUS, "country bonus added")
	check(GeoMath.round_points(100.0, false) == GeoMath.distance_points(100.0), "no bonus when wrong country")
	check(GeoMath.ROUND_MAX == 6000, "round max 6000")


func _format() -> void:
	check(GeoMath.format_distance(1234.4, false) == "1,234 km", "km grouping: " + GeoMath.format_distance(1234.4, false))
	check(GeoMath.format_distance(1609.344, true) == "1,000 mi", "miles: " + GeoMath.format_distance(1609.344, true))
	check(GeoMath.format_distance(3.25, false) == "3.2 km" or GeoMath.format_distance(3.25, false) == "3.3 km", "one decimal under 10")
	check(GeoMath.group_digits(30000) == "30,000", "group 30000")
	check(GeoMath.group_digits(999) == "999", "group 999")
	check(GeoMath.group_digits(1234567) == "1,234,567", "group millions")
	check(GeoMath.locale_uses_miles("en_US"), "en_US uses miles")
	check(GeoMath.locale_uses_miles("en-GB"), "en-GB uses miles")
	check(not GeoMath.locale_uses_miles("es_AR"), "es_AR uses km")
	check(not GeoMath.locale_uses_miles("en"), "bare en uses km")


func _projection() -> void:
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 500:
		var g := Vector2(rng.randf_range(-180, 180), rng.randf_range(-89, 89))
		var back := MapProjection.unproject(MapProjection.project(g))
		worst = maxf(worst, g.distance_to(back))
	check(worst < 1e-3, "project/unproject round trip (worst %.6f deg)" % worst)
	var size := MapProjection.map_size()
	check(near(MapProjection.project(Vector2(-180, 90)).x, 0.0, 1e-3) and near(MapProjection.project(Vector2(-180, 90)).y, 0.0, 1e-2), "top-left corner is (0,0)")
	check(near(MapProjection.project(Vector2(180, -90)).x, size.x, 1e-3), "right edge = map width")
	check(near(MapProjection.project(Vector2(0, 0)).y, size.y / 2.0, 1e-3), "equator at mid height")
	check(MapProjection.project(Vector2(0, 60)).y < MapProjection.project(Vector2(0, 30)).y, "north is up")
	# Screen transform round trip with zoom + offset.
	var z := 0.37
	var off := Vector2(-120, 55)
	var g2 := Vector2(-58.38, -34.6)
	var s := MapProjection.to_screen(g2, z, off)
	check(MapProjection.from_screen(s, z, off).distance_to(g2) < 1e-3, "screen round trip")
	check(MapProjection.unproject(Vector2(-50, -50)).x == -180.0, "unproject clamps")


func _geodesic() -> void:
	var a := Vector2(-74.0, 40.7)
	var b := Vector2(139.7, 35.7)
	var line := GeoMath.geodesic(a, b, 32)
	check(line.size() == 33, "geodesic has steps+1 points")
	check(line[0].distance_to(a) < 1e-3 and line[32].distance_to(b) < 1e-3, "geodesic endpoints")
	# NYC-Tokyo great circle goes far north (over Alaska/Arctic).
	var max_lat := -90.0
	for p in line:
		max_lat = maxf(max_lat, p.y)
	check(max_lat > 60.0, "NYC-Tokyo arcs north (max lat %.1f)" % max_lat)
	var total := 0.0
	for i in line.size() - 1:
		total += GeoMath.distance_km(line[i], line[i + 1])
	check(near(total, GeoMath.distance_km(a, b), 5.0), "geodesic length = great-circle distance")
	var cross := GeoMath.geodesic(Vector2(170, -15), Vector2(-170, -15), 16)
	var parts := GeoMath.split_antimeridian(cross)
	check(parts.size() == 2, "antimeridian split into 2 parts (%d)" % parts.size())
	var ok := true
	for part in parts:
		for i in part.size() - 1:
			if absf(part[i].x - part[i + 1].x) > 180.0:
				ok = false
	check(ok, "no part jumps across the map")
	check(GeoMath.split_antimeridian(GeoMath.geodesic(Vector2(0, 0), Vector2(10, 10))).size() == 1, "normal line not split")
