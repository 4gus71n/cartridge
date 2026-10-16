class_name PinpointGame
extends RefCounted
## One game: N photos, one guess each. Serialisable for resume.

const ROUNDS := 5

var photo_ids: Array[String] = []
var results: Array[Dictionary] = []  # one per finished round


func start(ids: Array[String]) -> void:
	photo_ids = ids.duplicate()
	results.clear()


func round_index() -> int:
	return results.size()


func is_over() -> bool:
	return photo_ids.size() > 0 and results.size() >= photo_ids.size()


func current_id() -> String:
	return "" if is_over() else photo_ids[results.size()]


## Score the current round. `truth`/`guess` are Vector2(lon, lat).
func submit(guess: Vector2, guess_country: String, truth: Vector2, truth_country: String) -> Dictionary:
	assert(not is_over())
	var km := GeoMath.distance_km(guess, truth)
	var ok := truth_country != "" and guess_country == truth_country
	var r := {
		"id": current_id(), "guess": [guess.x, guess.y], "truth": [truth.x, truth.y],
		"km": km, "country_ok": ok, "guess_country": guess_country,
		"distance_points": GeoMath.distance_points(km),
		"points": GeoMath.round_points(km, ok),
	}
	results.append(r)
	return r


func total() -> int:
	var t := 0
	for r in results:
		t += int(r.points)
	return t


func to_dict() -> Dictionary:
	return {"photo_ids": photo_ids.duplicate(), "results": results.duplicate(true)}


static func from_dict(d: Dictionary) -> PinpointGame:
	var g := PinpointGame.new()
	for id in d.get("photo_ids", []):
		g.photo_ids.append(String(id))
	for r in d.get("results", []):
		g.results.append(r)
	return g


static func guess_of(r: Dictionary) -> Vector2:
	return Vector2(float(r.guess[0]), float(r.guess[1]))


static func truth_of(r: Dictionary) -> Vector2:
	return Vector2(float(r.truth[0]), float(r.truth[1]))
