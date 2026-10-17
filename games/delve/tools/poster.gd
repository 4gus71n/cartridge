extends SceneTree
## Hermetic poster capture (needs a display, not --headless):
##   godot --path . --script tools/poster.gd -- [out.png] [lang] [margin]
## Boots the real main scene, stages a real mid-run fight on depth 6
## (explored floor, monsters closing in, an arrow in flight, loot nearby)
## with a narrower column so the key art sits in the central ~80 % width.

const TEST_PATH := "user://poster_capture.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "poster.png"
	var lang: String = args[1] if args.size() > 1 else "en"
	var margin: float = float(args[2]) if args.size() > 2 else 60.0
	root.size = Vector2i(720, 1280)
	await process_frame
	var settings := root.get_node("Settings")
	settings.load_from(TEST_PATH)
	settings.set_language(lang)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.side_margin = margin
	root.add_child(main)
	await process_frame
	var r := Run.create(Seeds.hash32(77))
	for d in 5:
		r.descend_sync()
	# Pick the most open floor cell as the arena centre.
	var best := Vector2i.ZERO
	var best_n := -1
	for c in r.lv.floor_cells():
		var n := 0
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if r.lv.tile(c.x + dx, c.y + dy) == Level.FLOOR:
					n += 1
		if n > best_n:
			best_n = n
			best = c
	r.lv.monsters.clear()
	r.lv.items = r.lv.items.filter(func(e: Dictionary) -> bool: return Run.cheb(e.x - best.x, e.y - best.y) > 4)
	r.px = best.x
	r.py = best.y
	r._reveal_map()
	for i in r.lv.seen.size():
		if r.lv.seen[i] == 1 and Vector2i(i % Level.W, i / Level.W).distance_to(best) > 16:
			r.lv.seen[i] = 0
	r.lv.traps.clear()
	var foes := [["orc", Vector2i(2, -1)], ["orc", Vector2i(3, 0)], ["archer", Vector2i(-3, -3)], ["spider", Vector2i(-2, 2)], ["wisp", Vector2i(1, 3)]]
	for f in foes:
		var p: Vector2i = best + f[1]
		if r.lv.tile(p.x, p.y) == Level.WALL:
			continue
		var m := Spawn.monster(f[0], p.x, p.y, r.rng)
		m.aw = true
		r.lv.monsters.append(m)
	r.lv.monsters[0].hp = int(r.lv.monsters[0].mhp) / 3
	r.lv.monsters[3].aw = false
	var loot := [["p_haste", Vector2i(-1, -2)], ["w_lightning", Vector2i(0, 2)], ["gold", Vector2i(-3, 1)], ["s_map", Vector2i(2, 2)]]
	for l in loot:
		var p: Vector2i = best + l[1]
		if r.lv.tile(p.x, p.y) != Level.WALL:
			var it := Spawn.item(l[0], 40 if l[0] == "gold" else 1)
			r.lv.items.append({"x": p.x, "y": p.y, "it": it, "s": true})
	r.lvl = 6
	r.xp = 390
	r.mhp = 44
	r.hp = 29
	r.gold = 312
	r.turns = 2410
	r.kills = 31
	r.update_fov()
	r.msgs.clear()
	r.msg({"f": "MSG_KILL", "a": ["#M_SKELETON"]}, 1)
	r.msg({"f": "MSG_YOU_HIT", "a": ["#M_ORC"]})
	r.msg({"f": "SHOOT_ARCHER", "a": ["#M_ARCHER"]})
	main.run = r
	main._show_game()
	main._refresh()
	var archer: Dictionary = r.lv.monsters[2]
	r.events.append({"e": "bolt", "a": Vector2i(archer.x, archer.y), "b": Vector2i(r.px, r.py), "c": "#f2d45c"})
	r.events.append({"e": "dmg", "x": r.lv.monsters[0].x, "y": r.lv.monsters[0].y, "n": 7, "id": r.lv.monsters[0].id})
	main.map_view.consume_events()
	main.map_view.bolts[0].t = 0.04
	for i in 3:
		await process_frame
	main.map_view.floaters[0].t = 0.15
	main.map_view.bolts[0].t = 0.06
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img.get_size() != Vector2i(720, 1280):
		img.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("poster: saved %s %s" % [out, img.get_size()])
	settings.clear_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)
