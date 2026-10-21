extends SceneTree
## Difficulty targets (v2): godot --headless --path . --script tests/difficulty_check.gd
## Deterministic hashed seeds; time-boxed (a few seconds).
##  * random bot (random rotation + column, hard drop): median survival <= 70
##    pieces over 40 seeds, and a small median score;
##  * greedy bot: median survival >= 2x the random bot (skill matters);
##  * do-nothing bot (centre column, no rotation): dead within ~30 pieces.

const Bot := preload("res://tests/prism_bot.gd")
const GREEDY_GAMES := 20
const GREEDY_CAP := 300

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var rnd := _measure("random", 40, 400)
	var ctr := _measure("centre", 40, 400)
	var grd := _measure("greedy", GREEDY_GAMES, GREEDY_CAP)
	check(rnd.pieces <= 70.0, "random bot median survival %.0f <= 70" % rnd.pieces)
	check(rnd.score <= 300.0, "random bot median score %.0f is small" % rnd.score)
	check(rnd.over == 40, "every random game ends (%d/40)" % rnd.over)
	check(rnd.match_rate < 0.25, "random placements rarely match (%.3f of pieces)" % rnd.match_rate)
	check(ctr.max <= 30, "do-nothing bot dead within 30 pieces (worst %d)" % ctr.max)
	check(ctr.over == 40, "every do-nothing game ends")
	check(grd.pieces >= 2.0 * rnd.pieces, "greedy median %.0f >= 2x random %.0f" % [grd.pieces, rnd.pieces])
	check(grd.score >= 20.0 * maxf(rnd.score, 1.0), "greedy median score %.0f dwarfs random %.0f" % [grd.score, rnd.score])
	check(grd.over >= GREEDY_GAMES / 2, "greedy bot also loses eventually (%d/%d before cap)" % [grd.over, GREEDY_GAMES])
	print("difficulty: random %.0f pcs / %.0f pts, centre %.0f pcs (max %d), greedy %.0f pcs / %.0f pts, %d ms" % [
		rnd.pieces, rnd.score, ctr.pieces, ctr.max, grd.pieces, grd.score, Time.get_ticks_msec() - t0])
	print("difficulty_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _measure(kind: String, games: int, cap: int) -> Dictionary:
	var pieces := []
	var scores := []
	var over := 0
	var matched := 0
	var total := 0
	for i in games:
		var r := Bot.play(kind, Bot.seed_for(i), cap)
		pieces.append(r.pieces)
		scores.append(r.score)
		matched += r.matching
		total += r.pieces
		if r.over:
			over += 1
	return {"pieces": Bot.median(pieces), "score": Bot.median(scores), "over": over,
		"max": pieces.max(), "match_rate": float(matched) / maxf(1.0, total)}
