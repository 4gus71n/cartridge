class_name Progress
extends RefCounted
## Level progress: best stars per level, which teaching blurbs were seen and
## in-progress drafts (current input + launches so far, so closing the app
## mid-level resumes it and does not reset the attempt count).
## Plain class (no scene dependency) so save/load is unit-tested.

var stars := {}       ## level index (int) -> best stars 1..3
var seen := {}        ## intro key -> true
var drafts := {}      ## level index (int) -> {"input": String, "tries": int}
var language := ""
var last_level := 0


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


## Stores a result (and drops the level's draft); returns true if it
## improved the record.
func record(level: int, s: int) -> bool:
	drafts.erase(level)
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


func set_draft(level: int, input: String, tries: int) -> void:
	drafts[level] = {"input": input, "tries": tries}


func draft(level: int) -> Dictionary:
	return drafts.get(level, {})


func save_to(path: String) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", language)
	cfg.set_value("general", "last_level", last_level)
	var s := {}
	for k in stars:
		s[str(k)] = int(stars[k])
	cfg.set_value("progress", "stars", s)
	cfg.set_value("progress", "seen", seen.keys())
	var d := {}
	for k in drafts:
		d[str(k)] = drafts[k]
	cfg.set_value("progress", "drafts", d)
	return cfg.save(path)


func load_from(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	language = str(cfg.get_value("general", "language", ""))
	last_level = maxi(0, int(cfg.get_value("general", "last_level", 0)))
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
	drafts.clear()
	var d = cfg.get_value("progress", "drafts", {})
	if d is Dictionary:
		for k in d:
			var e = d[k]
			if str(k).is_valid_int() and e is Dictionary:
				drafts[int(k)] = {"input": str(e.get("input", "")), "tries": maxi(0, int(e.get("tries", 0)))}
	return true
