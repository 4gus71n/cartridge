class_name PhotoDeck
extends RefCounted
## The bundled photo manifest (content/photos.json) and round selection.

const MANIFEST := "res://content/photos.json"
const PHOTO_DIR := "res://content/photos/"
## Only these licenses may ship (roadmap §3). Short names as stored in the manifest.
const ALLOWED_LICENSES := ["CC0", "Public domain", "CC BY 4.0", "CC BY 3.0", "CC BY 2.0"]

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


func load_texture(photo: Dictionary) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(PHOTO_DIR + String(photo.file))
	var img := Image.new()
	if bytes.is_empty() or img.load_webp_from_buffer(bytes) != OK:
		push_warning("could not load photo " + String(photo.file))
		return null
	return ImageTexture.create_from_image(img)


## Pick `n` distinct photo ids. Preference order: not recently seen, new
## country, new continent. Never repeats an id within the returned list.
func pick_round_ids(n: int, rng: RandomNumberGenerator, recent: Array = []) -> Array[String]:
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
	# Pass 0: fresh + new country + new continent; 1: fresh + new country;
	# 2: new country; 3: anything not yet chosen.
	for pass_i in 4:
		for p in pool:
			if chosen.size() >= n:
				return chosen
			var id := String(p.id)
			if id in chosen:
				continue
			if pass_i <= 1 and id in recent:
				continue
			if pass_i <= 2 and countries.has(p.country):
				continue
			if pass_i == 0 and continents.has(p.continent):
				continue
			chosen.append(id)
			countries[p.country] = true
			continents[p.continent] = true
	return chosen


## Returns a list of problems (empty = valid). Checks files + licenses.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var ids := {}
	for p in photos:
		for field in ["id", "file", "lat", "lon", "country", "continent", "author", "license", "source"]:
			if not p.has(field) or str(p[field]) == "":
				problems.append("%s: missing %s" % [p.get("id", "?"), field])
		if ids.has(p.id):
			problems.append("duplicate id " + str(p.id))
		ids[p.id] = true
		if not String(p.license) in ALLOWED_LICENSES:
			problems.append("%s: license not allowed: %s" % [p.id, p.license])
		if not FileAccess.file_exists(PHOTO_DIR + String(p.file)):
			problems.append("%s: file missing %s" % [p.id, p.file])
		if absf(float(p.lat)) > 90.0 or absf(float(p.lon)) > 180.0:
			problems.append("%s: bad coordinates" % p.id)
		if not String(p.source).begins_with("https://commons.wikimedia.org/wiki/File:"):
			problems.append("%s: bad source url" % p.id)
	return problems
