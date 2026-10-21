class_name PhotoDeck
extends RefCounted
## The bundled photo manifest (content/photos.json) and round selection.

const MANIFEST := "res://content/photos.json"
const PHOTO_DIR := "res://content/photos/"
## Only these licenses may ship (roadmap §3). Short names as stored in the manifest.
const ALLOWED_LICENSES := ["CC0", "Public domain", "CC BY 4.0", "CC BY 3.0", "CC BY 2.5", "CC BY 2.0"]
const DIFFICULTIES := ["easy", "medium", "hard"]
## Per-photo file size ceiling (content pipeline encodes to <= 34 KB).
const MAX_PHOTO_BYTES := 36 * 1024
## Round difficulty mix by experience: more hard rounds the more games you played.
const MIX_NOVICE := ["easy", "easy", "medium", "medium", "hard"]
const MIX_REGULAR := ["easy", "medium", "medium", "hard", "hard"]
const MIX_VETERAN := ["easy", "medium", "hard", "hard", "hard"]
const REGULAR_AFTER := 4
const VETERAN_AFTER := 12

var photos: Array[Dictionary] = []
var by_id := {}


static func load_default() -> PhotoDeck:
	var d := PhotoDeck.new()
	d.load_manifest(MANIFEST)
	return d


func load_manifest(path: String) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("photo manifest missing")
		return false
	for p in data.photos:
		var photo: Dictionary = p
		photos.append(photo)
		by_id[String(photo.id)] = photo
	return true


static func geo_of(photo: Dictionary) -> Vector2:
	return Vector2(float(photo.lon), float(photo.lat))


static func credit_line(photo: Dictionary) -> String:
	return "%s · %s · Wikimedia Commons" % [photo.author, photo.license]


static func difficulty_of(photo: Dictionary) -> String:
	var d := String(photo.get("difficulty", "medium"))
	return d if d in DIFFICULTIES else "medium"


func load_texture(photo: Dictionary) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(PHOTO_DIR + String(photo.file))
	var img := Image.new()
	if bytes.is_empty() or img.load_webp_from_buffer(bytes) != OK:
		push_warning("could not load photo " + String(photo.file))
		return null
	return ImageTexture.create_from_image(img)


## How many photos of each tier the pack holds.
func difficulty_counts() -> Dictionary:
	var out := {"easy": 0, "medium": 0, "hard": 0}
	for p in photos:
		var d := difficulty_of(p)
		out[d] = int(out[d]) + 1
	return out


## The wanted difficulty per round for a player with `games_played` games.
static func difficulty_mix(n: int, games_played: int) -> Array[String]:
	var pattern := MIX_NOVICE
	if games_played >= VETERAN_AFTER:
		pattern = MIX_VETERAN
	elif games_played >= REGULAR_AFTER:
		pattern = MIX_REGULAR
	var mix: Array[String] = []
	for i in n:
		mix.append(String(pattern[i % pattern.size()]))
	return mix


## Pick `n` distinct photo ids: a difficulty mix that hardens as the player
## plays more games, all from different countries, avoiding recently seen
## photos. Never repeats an id within the returned list.
func pick_round_ids(n: int, rng: RandomNumberGenerator, recent: Array = [],
		games_played: int = 0) -> Array[String]:
	var pool: Array[Dictionary] = photos.duplicate()
	# Fisher-Yates with our rng so games are reproducible from a seed.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var chosen: Array[String] = []
	var countries := {}
	var continents := {}
	for want in difficulty_mix(n, games_played):
		# Relaxation ladder: exact tier + fresh + new continent, then drop the
		# continent, the tier, the freshness and finally the country rule.
		for level in 5:
			var id := _take(pool, chosen, countries, continents, recent, want, level)
			if id != "":
				var p: Dictionary = by_id[id]
				chosen.append(id)
				countries[p.country] = true
				continents[p.continent] = true
				break
		if chosen.size() >= n:
			break
	return chosen


func _take(pool: Array[Dictionary], chosen: Array[String], countries: Dictionary,
		continents: Dictionary, recent: Array, want: String, level: int) -> String:
	for p in pool:
		var id := String(p.id)
		if id in chosen:
			continue
		if level <= 0 and continents.has(p.continent):
			continue
		if level <= 1 and difficulty_of(p) != want:
			continue
		if level <= 2 and id in recent:
			continue
		if level <= 3 and countries.has(p.country):
			continue
		return id
	return ""


## Returns a list of problems (empty = valid). Checks fields, licenses,
## difficulty tags, coordinates, files and the per-file size budget.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var ids := {}
	var files := {}
	for p in photos:
		for field in ["id", "file", "lat", "lon", "country", "continent", "author",
				"license", "license_url", "source", "place", "difficulty"]:
			if not p.has(field) or str(p[field]) == "":
				problems.append("%s: missing %s" % [p.get("id", "?"), field])
		if ids.has(p.id):
			problems.append("duplicate id " + str(p.id))
		ids[p.id] = true
		if files.has(p.get("file", "")):
			problems.append("duplicate file " + str(p.get("file", "")))
		files[p.get("file", "")] = true
		if not String(p.license) in ALLOWED_LICENSES:
			problems.append("%s: license not allowed: %s" % [p.id, p.license])
		if not difficulty_of(p) == String(p.get("difficulty", "")):
			problems.append("%s: bad difficulty: %s" % [p.id, p.get("difficulty", "")])
		var path := PHOTO_DIR + String(p.file)
		if not FileAccess.file_exists(path):
			problems.append("%s: file missing %s" % [p.id, p.file])
		else:
			var size := FileAccess.get_file_as_bytes(path).size()
			if size > MAX_PHOTO_BYTES:
				problems.append("%s: file too big (%d bytes)" % [p.id, size])
		if absf(float(p.lat)) > 90.0 or absf(float(p.lon)) > 180.0:
			problems.append("%s: bad coordinates" % p.id)
		if float(p.lat) == 0.0 and float(p.lon) == 0.0:
			problems.append("%s: null coordinates" % p.id)
		if not String(p.source).begins_with("https://commons.wikimedia.org/wiki/File:"):
			problems.append("%s: bad source url" % p.id)
		if String(p.license).begins_with("CC BY") and not String(p.license_url).begins_with("http"):
			problems.append("%s: CC BY needs a license url" % p.id)
	return problems
