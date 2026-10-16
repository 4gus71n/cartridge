extends SceneTree
## Hermetic poster capture (needs a display, not --headless):
##   godot --path . --script tools/poster.gd -- [out.png] [lang]
## Boots the real main scene, stages a busy mid-game board, triggers a real
## resolve step (chain x2 + prism line) and grabs the viewport mid-clear.

const TEST_PATH := "user://poster_capture.cfg"

# Column heights (col 4 is the open well, as in real play: a column of gems
# reaching the floor everywhere would complete the bottom prism line).
const HEIGHTS := [9, 10, 8, 7, 0, 6, 8, 10, 9]
# Intended clears: [hue, [[x, y], ...]] (y from the top of a 16-row well).
const GROUPS := [
	[1, [[0, 7], [1, 7], [1, 6], [2, 8], [1, 8], [0, 8]]],
	[3, [[7, 6], [8, 7], [7, 7], [7, 8], [6, 8]]],
]


func _stage(b: PrismBoard) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var fixed := {}
	for g in GROUPS:
		for c in g[1]:
			fixed[b.index(c[0], c[1])] = g[0]
	for x in b.width:
		for y in range(b.height - HEIGHTS[x], b.height):
			var i := b.index(x, y)
			b.grid[i] = fixed.get(i, rng.randi_range(1, 4))
	# Re-roll stray cells until only the intended groups would clear.
	for it in 2000:
		var found := b.find_clears()
		var bad := []
		for i in found.cells:
			if not fixed.has(i):
				bad.append(i)
		var leaks := false
		for g in found.groups:
			if g.size() != _group_size_of(g[0], fixed):
				leaks = true
				for i in g:
					if not fixed.has(i):
						bad.append(i)
		if bad.is_empty() and not leaks:
			return
		if bad.is_empty():
			# A fixed group touches a same-hue stray neighbour we missed: re-roll all neighbours.
			for i in fixed:
				for d in [1, -1, b.width, -b.width]:
					var j: int = i + d
					if j >= 0 and j < b.grid.size() and b.grid[j] != 0 and not fixed.has(j):
						bad.append(j)
		var k: int = bad[rng.randi_range(0, bad.size() - 1)]
		b.grid[k] = rng.randi_range(1, 4)


func _group_size_of(i: int, fixed: Dictionary) -> int:
	for g in GROUPS:
		for c in g[1]:
			if c[1] * 9 + c[0] == i:
				return g[1].size()
	return -1


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "poster.png"
	var lang: String = args[1] if args.size() > 1 else "en"
	await process_frame # let the Settings autoload run _ready() first
	var settings := root.get_node("Settings")
	settings.load_from(TEST_PATH)
	settings.set_language(lang)
	settings.best_score = 24860
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game(31)
	for i in 3:
		await process_frame
	var b: PrismBoard = main.board
	_stage(b)
	b.score = 18420
	b.level = 4
	b.cleared_cells = 3 * PrismBoard.CELLS_PER_LEVEL + 12
	b.combo = 2
	main._last_level = 4
	# Falling piece up high so the ghost shows.
	var p := Pieces.make("I", [2, 4])
	p.cells = p.rotated_cells(1)
	p.pos = Vector2i(4, 3)
	b.current = p
	main.view._piece_ref = p
	main.view._piece_vis = Vector2(p.pos)
	b.held = Pieces.make("Y", [2, 4])
	main._status_label.text = tr("COMBO") % 3
	main._update_hud()
	# Real resolution step, as if a chain is under way.
	var check := b.find_clears()
	print("poster: groups=%s rows=%s" % [check.groups, check.rows])
	b.chain = 1
	var gid: int = main._game_id
	var step := b.resolve_step()
	b.current = p # resolve_step leaves the piece alone; keep it drawn
	b.state = PrismBoard.State.PLAYING
	main.view.animate_clear(step)
	main.paused = true # freeze gravity while we capture
	var t := 0.0
	while t < 0.2:
		await process_frame
		t += main.get_process_delta_time()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img.get_size() != Vector2i(720, 1280):
		img.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
	img.save_png(out)
	print("poster: saved %s %s (game %d)" % [out, img.get_size(), gid])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0)
