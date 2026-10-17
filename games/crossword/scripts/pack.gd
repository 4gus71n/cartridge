class_name Pack
extends RefCounted
## Loads the bundled puzzle pack for a language and picks the daily puzzle.

const PATH := "res://data/puzzles_%s.json"


static func load_pack(lang: String) -> Array[Puzzle]:
	var out: Array[Puzzle] = []
	var f := FileAccess.open(PATH % lang, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		for d in data:
			out.append(Puzzle.from_dict(d))
	return out


## Local calendar day number (days since 1970-01-01).
static func today() -> int:
	var t: float = Time.get_unix_time_from_system() + float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	return int(floor(t / 86400.0))


## Deterministic daily pick that walks the whole pack before repeating.
static func daily_index(day: int, count: int) -> int:
	if count <= 0:
		return 0
	return posmod(day * 17 + 5, count)


## Formats seconds as m:ss.
static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
