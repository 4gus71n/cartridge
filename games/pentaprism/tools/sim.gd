extends SceneTree
## Difficulty measurement (not part of the gate):
##   godot --headless --path . --script tools/sim.gd -- <bot> <games> <cap> [key=value ...]
## bot: random | centre | greedy | all. Tuning keys: palette, min_group,
## stone_start, stone_min. Prints medians over hashed deterministic seeds.

const Bot := preload("res://tests/prism_bot.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kind: String = args[0] if args.size() > 0 else "all"
	var games: int = int(args[1]) if args.size() > 1 else 40
	var cap: int = int(args[2]) if args.size() > 2 else 400
	var tune := {}
	for a in args.slice(3):
		var kv: PackedStringArray = a.split("=")
		if kv[0] == "palette":
			Pieces.palette = int(kv[1])
		else:
			tune[kv[0]] = int(kv[1])
	var kinds := ["random", "centre", "greedy"] if kind == "all" else [kind]
	for k in kinds:
		var t0 := Time.get_ticks_msec()
		var pieces := []
		var scores := []
		var levels := []
		var clearing := []
		var matching := 0
		var total := 0
		var capped := 0
		var reasons := {}
		for i in games:
			var r := Bot.play(k, Bot.seed_for(i), cap, tune)
			pieces.append(r.pieces)
			scores.append(r.score)
			levels.append(r.level)
			matching += r.matching
			total += r.pieces
			clearing.append(float(r.clearing) / maxf(1.0, r.pieces))
			reasons[r.reason] = reasons.get(r.reason, 0) + 1
			if not r.over:
				capped += 1
		pieces.sort()
		print("%-7s n=%d cap=%d palette=%d %s | pieces med %.0f (min %d max %d) | score med %.0f | level med %.0f | clearing-piece rate %.2f | match-piece rate %.3f | capped %d %s | %d ms" % [
			k, games, cap, Pieces.palette, tune, Bot.median(pieces), pieces[0], pieces[-1],
			Bot.median(scores), Bot.median(levels), Bot.median(clearing), float(matching) / maxf(1, total), capped, reasons, Time.get_ticks_msec() - t0])
	quit(0)
