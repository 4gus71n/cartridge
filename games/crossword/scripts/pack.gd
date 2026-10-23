class_name Pack
extends RefCounted
## Loads the bundled puzzle pack for a language and picks the daily puzzle.

const PATH := "res://data/puzzles_%s.json"
## Tiers that ship today. 9x9 ("big") is authored but not shipped yet: see
## tools/wip/README.md.
const TIERS := ["mini", "midi"]
## Which tier the daily puzzle uses, by ISO weekday (1 = Monday): the week
## starts easy and the weekend is the harder grid.
const DAILY_TIER := {1: "mini", 2: "mini", 3: "mini", 4: "midi", 5: "midi",
		6: "midi", 7: "midi"}


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


## ISO weekday of a day number (1 = Monday ... 7 = Sunday).
## Day 0 is 1970-01-01, a Thursday.
static func weekday(day: int) -> int:
	return posmod(day + 3, 7) + 1


## Tier the daily puzzle uses on `day`: easier early in the week, big at the weekend.
static func daily_tier(day: int) -> String:
	return DAILY_TIER[weekday(day)]


## Indices of every puzzle of `tier`, in pack order.
static func tier_indices(pack: Array, tier: String) -> Array[int]:
	var out: Array[int] = []
	for i in pack.size():
		if pack[i].tier == tier:
			out.append(i)
	return out


## The day's puzzle: its tier follows the weekday, and successive days of the
## same tier walk that whole tier before any puzzle repeats.
static func daily_index(pack: Array, day: int) -> int:
	var tier := daily_tier(day)
	var idx := tier_indices(pack, tier)
	if idx.is_empty():
		return 0
	# How many days of this tier have passed: a stride coprime with the tier
	# size then covers every puzzle before coming back round.
	var n := 0
	for d in range(0, day):
		if daily_tier(d) == tier:
			n += 1
	var stride := 1
	for s in range(idx.size() / 2, 0, -1):
		if _coprime(s, idx.size()):
			stride = s
			break
	return idx[posmod(n * stride, idx.size())]


static func _coprime(a: int, b: int) -> bool:
	while b != 0:
		var r := a % b
		a = b
		b = r
	return a == 1


## Next puzzle of `tier` after `from_index`, skipping any that `is_solved`
## accepts, so a solved puzzle is never served while one is still unsolved.
## When the whole tier is solved it simply cycles.
static func next_in_tier(pack: Array, tier: String, from_index: int, is_solved: Callable) -> int:
	var idx := tier_indices(pack, tier)
	if idx.is_empty():
		return from_index
	var start := idx.find(from_index)
	for step in range(1, idx.size() + 1):
		var cand: int = idx[posmod(start + step, idx.size())]
		if not is_solved.call(pack[cand].id):
			return cand
	return idx[posmod(start + 1, idx.size())]


## Formats seconds as m:ss.
static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
