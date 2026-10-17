extends SceneTree
## World map data: loads, every ring triangulates, point-in-country for known
## places (incl. enclaves and islands), sea, names in both languages.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldData.load_default()
	var t1 := Time.get_ticks_msec()
	check(w.countries.size() > 200, "200+ countries (%d)" % w.countries.size())
	check(w.point_count > 10000, "polygon points loaded (%d)" % w.point_count)
	var palette := PackedColorArray([Color.RED, Color.GREEN])
	var built := w.build_land_mesh(palette)
	var t2 := Time.get_ticks_msec()
	check(int(built.failed) == 0, "every ring triangulates (failed %d)" % built.failed)
	check(int(built.triangles) > 10000, "land mesh has triangles (%d)" % built.triangles)
	print("  load %d ms, mesh %d ms" % [t1 - t0, t2 - t1])
	var places := {
		"FRA": Vector2(2.3522, 48.8566), "JPN": Vector2(139.6503, 35.6762), "USA": Vector2(-74.006, 40.7128),
		"ARG": Vector2(-58.3816, -34.6037), "AUS": Vector2(151.2093, -33.8688), "EGY": Vector2(31.2357, 30.0444),
		"BRA": Vector2(-43.1729, -22.9068), "IND": Vector2(77.209, 28.6139), "ZAF": Vector2(18.4241, -33.9249),
		"LSO": Vector2(27.48, -29.31), "CHE": Vector2(7.7491, 46.0207), "ISL": Vector2(-21.9426, 64.1466),
		"NZL": Vector2(174.7633, -36.8485), "MLT": Vector2(14.42, 35.89), "SGP": Vector2(103.82, 1.35),
		"ESP": Vector2(-3.7038, 40.4168), "PRT": Vector2(-9.1394, 38.7139), "CAN": Vector2(-79.3832, 43.6532),
		"GRL": Vector2(-51.0986, 69.2198), "ATA": Vector2(0.0, -80.0), "RUS": Vector2(37.6173, 55.7558),
		"GRC": Vector2(25.43, 36.42),
	}
	for key in places:
		var got := w.country_at(places[key])
		check(got == key, "%s contains %s (got '%s')" % [key, places[key], got])
	check(w.country_at(Vector2(-30.0, 30.0)) == "", "mid-Atlantic is sea")
	check(w.country_at(Vector2(-74.0, 40.0), 0.0) == "", "off New Jersey is sea without snapping")
	check(w.country_at(Vector2(-73.9, 40.2)) == "USA", "just off the coast snaps to USA")
	check(w.country_at(Vector2(-71.0, 39.0)) == "", "200 km offshore stays sea")
	check(w.country_at(Vector2(-150.0, -10.0)) == "", "mid-Pacific is sea")
	check(w.country_name("ESP", "en") == "Spain", "Spain (en)")
	check(w.country_name("ESP", "es") == "España", "España (es): " + w.country_name("ESP", "es"))
	check(w.country_name("DEU", "es") == "Alemania", "Alemania (es)")
	check(w.country_name("nope", "en") == "", "unknown key -> empty")
	var segs := w.border_segments()
	check(segs.size() > 0 and segs.size() % 2 == 0, "border segments come in pairs")
	var only := w.build_land_mesh(palette, "ITA")
	check(int(only.triangles) > 0 and int(only.triangles) < int(built.triangles), "single-country highlight mesh")
	print("world_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
