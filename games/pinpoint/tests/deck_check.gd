extends SceneTree
## Photo manifest: every entry valid (fields, licence allow-list, coordinates,
## country matching the bundled map, file present and inside the size budget),
## no duplicates, distribution limits (countries, continents, places),
## difficulty tags, and round selection (difficulty mix, no repeats, varied
## countries, avoids recently seen, seeded/reproducible).

const MIN_PHOTOS := 600
const MIN_COUNTRIES := 140
const MAX_PER_COUNTRY := 8
const MAX_PER_PLACE := 2
const PHOTO_BUDGET_BYTES := 19 * 1024 * 1024  # keeps the zipped build <= ~30 MB
const MAX_SIDE := 780

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
	_distribution(deck)
	_rounds(deck)
	_recent(deck)
	print("deck_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _manifest(deck: PhotoDeck, world: WorldData) -> void:
	var n := deck.photos.size()
	check(n >= MIN_PHOTOS, "at least %d photos (%d)" % [MIN_PHOTOS, n])
	var problems := deck.validate()
	for p in problems.slice(0, 10):
		printerr("  ", p)
	check(problems.is_empty(), "manifest validates (%d problems)" % problems.size())
	for bad in ["CC BY-SA 4.0", "CC BY-SA 3.0", "CC BY-NC 4.0", "CC BY-ND 4.0", "GFDL"]:
		check(not PhotoDeck.ALLOWED_LICENSES.has(bad), "%s is not allowed" % bad)
	var bytes := 0
	var decoded := 0
	var bad_country := 0
	var max_side := 0
	var biggest := 0
	for p in deck.photos:
		var path := PhotoDeck.PHOTO_DIR + String(p.file)
		var size := FileAccess.get_file_as_bytes(path).size()
		bytes += size
		biggest = maxi(biggest, size)
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
	check(decoded == n, "every photo decodes (%d/%d)" % [decoded, n])
	check(max_side <= MAX_SIDE, "photos are small (max side %d)" % max_side)
	check(biggest <= PhotoDeck.MAX_PHOTO_BYTES, "biggest photo %d bytes" % biggest)
	check(bad_country == 0, "photo countries agree with the map (%d bad)" % bad_country)
	check(bytes <= PHOTO_BUDGET_BYTES, "photos <= %d MB (%.1f MB)"
			% [PHOTO_BUDGET_BYTES / 1048576, bytes / 1048576.0])
	print("  %d photos, %.1f MB, avg %.0f KB" % [n, bytes / 1048576.0, bytes / float(n) / 1024.0])
	# Credits list every single source.
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	var missing := 0
	for p in deck.photos:
		if credits.find(String(p.source)) < 0:
			missing += 1
	check(missing == 0, "CREDITS.md lists every photo source (%d missing)" % missing)
	# validate() rejects a broken entry.
	var bad := PhotoDeck.new()
	bad.photos.append({"id": "x", "file": "nope.webp", "lat": 0, "lon": 0, "country": "FRA",
		"continent": "EU", "place": "p", "difficulty": "nope", "author": "a",
		"license": "CC BY-SA 4.0", "license_url": "https://x", "source": "https://example.com"})
	var bp := bad.validate()
	check(bp.size() >= 4, "validate flags licence, difficulty, missing file, bad source, null coords (%d)" % bp.size())


func _distribution(deck: PhotoDeck) -> void:
	var countries := {}
	var conts := {}
	var places := {}
	var diffs := {}
	for p in deck.photos:
		countries[p.country] = int(countries.get(p.country, 0)) + 1
		conts[p.continent] = int(conts.get(p.continent, 0)) + 1
		var place_key := "%s|%s" % [String(p.place), String(p.country)]
		places[place_key] = int(places.get(place_key, 0)) + 1
		var d := PhotoDeck.difficulty_of(p)
		diffs[d] = int(diffs.get(d, 0)) + 1
	check(countries.size() >= MIN_COUNTRIES, "%d+ countries (%d)" % [MIN_COUNTRIES, countries.size()])
	var over_country := []
	for k in countries:
		if int(countries[k]) > MAX_PER_COUNTRY:
			over_country.append("%s=%d" % [k, countries[k]])
	check(over_country.is_empty(), "<= %d photos per country (%s)" % [MAX_PER_COUNTRY, ", ".join(over_country)])
	var over_place := []
	for k in places:
		if int(places[k]) > MAX_PER_PLACE:
			over_place.append("%s=%d" % [k, places[k]])
	check(over_place.is_empty(), "<= %d photos per place (%s)" % [MAX_PER_PLACE, ", ".join(over_place)])
	var n := deck.photos.size()
	# Every inhabited continent must carry real weight, but they are not equal:
	# South America holds ~6% of the world's people and far less of Commons'
	# licence-clean geotagged photography, so it gets its own floor.
	for c in ["EU", "AS", "AF", "NA"]:
		var share := int(conts.get(c, 0)) / float(n)
		check(share >= 0.08, "continent %s has >= 8%% of the pack (%d, %.1f%%)"
				% [c, conts.get(c, 0), share * 100.0])
	var sa_share := int(conts.get("SA", 0)) / float(n)
	check(sa_share >= 0.06, "continent SA has >= 6%% of the pack (%d, %.1f%%)"
			% [conts.get("SA", 0), sa_share * 100.0])
	check(int(conts.get("OC", 0)) >= 15, "Oceania represented (%d)" % conts.get("OC", 0))
	check(int(conts.get("AN", 0)) >= 3, "Antarctica represented (%d)" % conts.get("AN", 0))
	for d in PhotoDeck.DIFFICULTIES:
		check(int(diffs.get(d, 0)) >= 40, "difficulty %s has >= 40 photos (%d)" % [d, diffs.get(d, 0)])
	print("  continents %s" % [conts])
	print("  difficulty %s, %d countries, %d places" % [diffs, countries.size(), places.size()])


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
	# Difficulty mix: exactly what the tier asks for, and harder with experience.
	check(PhotoDeck.difficulty_mix(5, 0) == PhotoDeck.MIX_NOVICE, "novice mix")
	check(PhotoDeck.difficulty_mix(5, 6) == PhotoDeck.MIX_REGULAR, "regular mix")
	check(PhotoDeck.difficulty_mix(5, 40) == PhotoDeck.MIX_VETERAN, "veteran mix")
	check(PhotoDeck.difficulty_mix(3, 0).size() == 3, "mix adapts to round count")
	var tier_hard := {0: 0, 6: 0, 40: 0}
	var exact := 0
	var games := 60
	for tier in tier_hard:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(tier + 11)
		for g in games:
			var want := PhotoDeck.difficulty_mix(5, tier)
			var ids := deck.pick_round_ids(5, rng, [], tier)
			var got := []
			for id in ids:
				got.append(PhotoDeck.difficulty_of(deck.by_id[id]))
			got.sort()
			want.sort()
			if got == want:
				exact += 1
			for d in got:
				if d == "hard":
					tier_hard[tier] = int(tier_hard[tier]) + 1
	check(exact >= games * 3 * 0.9, "requested difficulty mix is met (%d/%d games)" % [exact, games * 3])
	check(tier_hard[0] < tier_hard[6] and tier_hard[6] < tier_hard[40],
			"more hard rounds with experience (%s)" % [tier_hard])
	# A game always contains at least one easy and one hard photo.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242
	var mixed := true
	for g in 60:
		var ids := deck.pick_round_ids(5, rng2, [], g)
		var tiers := {}
		for id in ids:
			tiers[PhotoDeck.difficulty_of(deck.by_id[id])] = true
		if not (tiers.has("easy") and tiers.has("hard")):
			mixed = false
	check(mixed, "every game mixes easy and hard photos")


func _recent(deck: PhotoDeck) -> void:
	# Recently seen photos are avoided while fresh ones remain, with the
	# recent list scaled to the (much bigger) pack.
	var cap := clampi(int(deck.photos.size() / 3.0), 30, 150)
	check(cap >= 90, "recent capacity scales with the pack (%d)" % cap)
	var recent: Array = []
	var overlap := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for g in 30:
		var ids := deck.pick_round_ids(5, rng, recent, g)
		for id in ids:
			if id in recent:
				overlap += 1
			recent.append(id)
		while recent.size() > cap:
			recent.pop_front()
	check(overlap == 0, "30 consecutive games never repeat a recent photo (%d repeats)" % overlap)
	# Even with everything recent, a full game is still produced.
	var every: Array = []
	for p in deck.photos:
		every.append(p.id)
	var ids2 := deck.pick_round_ids(5, rng, every, 3)
	check(ids2.size() == 5, "all-recent pool still yields 5 photos")
	var cs := {}
	for id in ids2:
		cs[deck.by_id[id].country] = true
	check(cs.size() == 5, "all-recent fallback still uses 5 countries")
