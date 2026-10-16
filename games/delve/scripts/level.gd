class_name Level
extends RefCounted
## One dungeon floor: tiles, explored memory, floor items, monsters, traps.
## Plain data + helpers; serialises to a Dictionary for the autosave.

const W := 36
const H := 44

enum { WALL, FLOOR, CORRIDOR, DOOR, OPEN_DOOR, STAIRS, UPSTAIRS }

var depth := 1
var tiles := PackedByteArray()
var seen := PackedByteArray()
var monsters: Array = [] # Dictionaries, see Run._new_monster
var items: Array = [] # {x, y, it: item dict, s: seen-by-player}
var traps := {} # idx -> {"t": type, "f": found}
var start := Vector2i.ZERO
var stairs := Vector2i(-1, -1)
var cave := false


func _init() -> void:
	tiles.resize(W * H)
	tiles.fill(WALL)
	seen.resize(W * H)


static func idx(x: int, y: int) -> int:
	return y * W + x


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func tile(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return WALL
	return tiles[y * W + x]


func passable(x: int, y: int) -> bool:
	var t := tile(x, y)
	return t != WALL


## Blocks line of sight.
func opaque(x: int, y: int) -> bool:
	var t := tile(x, y)
	return t == WALL or t == DOOR


## Projectiles and walking (without opening) blocked.
func solid(x: int, y: int) -> bool:
	var t := tile(x, y)
	return t == WALL or t == DOOR


func monster_at(x: int, y: int) -> Dictionary:
	for m in monsters:
		if m.x == x and m.y == y:
			return m
	return {}


func items_at(x: int, y: int) -> Array:
	var out := []
	for e in items:
		if e.x == x and e.y == y:
			out.append(e)
	return out


func floor_cells() -> Array:
	var out := []
	for y in H:
		for x in W:
			var t := tiles[y * W + x]
			if t == FLOOR:
				out.append(Vector2i(x, y))
	return out


func to_dict() -> Dictionary:
	return {
		"depth": depth, "tiles": tiles, "seen": seen, "monsters": monsters.duplicate(true),
		"items": items.duplicate(true), "traps": traps.duplicate(true), "start": [start.x, start.y],
		"stairs": [stairs.x, stairs.y], "cave": cave,
	}


static func from_dict(d: Dictionary) -> Level:
	var lv := Level.new()
	lv.depth = d.depth
	lv.tiles = d.tiles
	lv.seen = d.seen
	lv.monsters = d.monsters.duplicate(true)
	lv.items = d.items.duplicate(true)
	lv.traps = d.traps.duplicate(true)
	lv.start = Vector2i(d.start[0], d.start[1])
	lv.stairs = Vector2i(d.stairs[0], d.stairs[1])
	lv.cave = d.cave
	return lv
