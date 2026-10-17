extends SceneTree
## Photo manifest: valid fields, files exist and decode, licenses in the
## allow-list, size budget, countries agree with the map, credits listed;
## round selection: no repeats, varied countries, avoids recent, seeded.

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var deck := PhotoDeck.load_default()
	var world := WorldData.load_default()
	_manifest(deck, world)
	_rounds(deck)
	print("deck_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _manifest(deck: PhotoDeck, world: WorldData) -> void:
	var n := deck.photos.size()
	check(n >= 120, "at least 120 photos (%d)" % n)
	var problems := deck.validate()
	for p in problems.slice(0, 10):
		printerr("  ", p)
	check(problems.is_empty(), "manifest validates (%d problems)" % problems.size())
	check(not PhotoDeck.ALLOWED_LICENSES.has("CC BY-SA 4.0"), "CC BY-SA is not allowed")
	var bytes := 0
	var conts := {}
	var countries := {}
	var decoded := 0
	var bad_country := 0
	var max_side := 0
	for p in deck.photos:
		var path := PhotoDeck.PHOTO_DIR + String(p.file)
		bytes += FileAccess.get_file_as_bytes(path).size()
		conts[p.continent] = int(conts.get(p.continent, 0)) + 1
		countries[p.country] = true
		var tex := deck.load_texture(p)
		if tex:
			decoded += 1
			max_side = maxi(max_side, maxi(tex.get_width(), tex.get_height()))
		if not world.by_key.has(String(p.country)):
			bad_country += 1
			printerr("  unknown country ", p.id, " ", p.country)
		else:
			var at := world.country_at(PhotoDeck.geo_of(p))
			if at != "" and at != String(p.country):
				bad_country += 1
				printerr("  country mismatch ", p.id, " ", p.country, " vs map ", at)
		var lic := String(p.license)
		if lic.begins_with("CC BY"):
			check(String(p.author) != "", "%s: CC BY needs an author" % p.id)
	check(decoded == n, "every photo decodes (%d/%d)" % [decoded, n])
	check(max_side <= 960, "photos are small (max side %d)" % max_side)
	check(bad_country == 0, "photo countries agree with the map (%d bad)" % bad_country)
	check(bytes <= 15 * 1024 * 1024, "photos <= 15 MB (%.1f MB)" % (bytes / 1048576.0))
	for c in ["EU", "AS", "AF", "NA", "SA", "OC"]:
		check(int(conts.get(c, 0)) >= 8, "continent %s has >= 8 photos (%d)" % [c, conts.get(c, 0)])
	check(conts.has("AN"), "Antarctica represented")
	check(countries.size() >= 60, "60+ countries (%d)" % countries.size())
	print("  %d photos, %.1f MB, continents %s, %d countries" % [n, bytes / 1048576.0, conts, countries.size()])
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	var missing := 0
	for p in deck.photos:
		if credits.find(String(p.source)) < 0:
			missing += 1
	check(missing == 0, "CREDITS.md lists every photo source (%d missing)" % missing)
	# Validation catches a bad license.
	var bad := PhotoDeck.new()
	bad.photos.append({"id": "x", "file": "nope.webp", "lat": 0, "lon": 0, "country": "FRA", "continent": "EU",
		"author": "a", "license": "CC BY-SA 4.0", "source": "https://example.com"})
	var bp := bad.validate()
	check(bp.size() >= 3, "validate flags license, missing file and bad source (%d)" % bp.size())


func _rounds(deck: PhotoDeck) -> void:
	var all_ok := true
	var country_ok := true
	for s in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(s)
		var ids := deck.pick_round_ids(5, rng)
		var seen := {}
		var cs := {}
		for id in ids:
			if seen.has(id) or not deck.by_id.has(id):
				all_ok = false
			seen[id] = true
			cs[deck.by_id[id].country] = true
		if ids.size() != 5:
			all_ok = false
		if cs.size() != 5:
			country_ok = false
	check(all_ok, "200 games: 5 distinct valid photos each")
	check(country_ok, "200 games: 5 different countries each")
	var a := RandomNumberGenerator.new()
	a.seed = hash(7)
	var b := RandomNumberGenerator.new()
	b.seed = hash(7)
	check(deck.pick_round_ids(5, a) == deck.pick_round_ids(5, b), "same seed -> same photos")
	# Recently seen photos are avoided while fresh ones remain.
	var recent: Array = []
	var overlap := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	for g in 15:
		var ids := deck.pick_round_ids(5, rng2, recent)
		for id in ids:
			if id in recent:
				overlap += 1
			recent.append(id)
		while recent.size() > 90:
			recent.pop_front()
	check(overlap == 0, "15 consecutive games never repeat a recent photo (%d repeats)" % overlap)
	# Even with everything recent, a full game is still produced.
	var every: Array = []
	for p in deck.photos:
		every.append(p.id)
	var ids2 := deck.pick_round_ids(5, rng2, every)
	check(ids2.size() == 5, "all-recent pool still yields 5 photos")
