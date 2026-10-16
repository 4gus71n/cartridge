class_name Progress
extends RefCounted
## Level progress: best stars per level + which teaching blurbs were seen.
## Plain class (no scene dependency) so save/load is unit-tested.

var stars := {}       ## level index (int) -> best stars 1..3
var seen := {}        ## intro key -> true
var language := ""


## Stars for solving a level after `attempts` launches.
static func stars_for_attempts(attempts: int) -> int:
	if attempts <= 1:
		return 3
	if attempts <= 3:
		return 2
	return 1


func best(level: int) -> int:
	return int(stars.get(level, 0))


func solved(level: int) -> bool:
	return best(level) > 0


func unlocked(level: int) -> bool:
	return level == 0 or solved(level - 1) or solved(level)


## Stores a result; returns true if it improved the record.
func record(level: int, s: int) -> bool:
	if s > best(level):
		stars[level] = clampi(s, 1, 3)
		return true
	return false


func total_stars() -> int:
	var t := 0
	for k in stars:
		t += int(stars[k])
	return t


## First unsolved level (or the last level when everything is solved).
func next_level(level_count: int) -> int:
	for i in level_count:
		if not solved(i):
			return i
	return level_count - 1


func save_to(path: String) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", language)
	var s := {}
	for k in stars:
		s[str(k)] = int(stars[k])
	cfg.set_value("progress", "stars", s)
	cfg.set_value("progress", "seen", seen.keys())
	return cfg.save(path)


func load_from(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	language = str(cfg.get_value("general", "language", ""))
	stars.clear()
	var s = cfg.get_value("progress", "stars", {})
	if s is Dictionary:
		for k in s:
			var v := int(s[k])
			if str(k).is_valid_int() and v >= 1 and v <= 3:
				stars[int(k)] = v
	seen.clear()
	var sn = cfg.get_value("progress", "seen", [])
	if sn is Array:
		for k in sn:
			seen[str(k)] = true
	return true
