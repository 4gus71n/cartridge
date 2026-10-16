class_name RunState
extends RefCounted
## One Endless run: lives, score, streak and the shrinking answer timer.

const START_LIVES := 3
const BASE_POINTS := 100
const SPEED_POINTS := 100
const START_TIME := 4.5
const MIN_TIME := 2.0
const TIME_STEP := 0.125 # seconds removed per streak step (2.0 s at streak 20)
const STREAK_PER_MULT := 5
const MAX_MULT := 5
const WARMUP_QUESTIONS := 5 # first questions have 3 choices, then 4

var lives := START_LIVES
var score := 0
var streak := 0
var best_streak := 0
var correct := 0
var answered := 0
var missed: Array[String] = []


## Seconds allowed for the current question.
func time_limit() -> float:
	return maxf(MIN_TIME, START_TIME - TIME_STEP * streak)


func multiplier() -> int:
	return mini(1 + streak / STREAK_PER_MULT, MAX_MULT)


func choice_count() -> int:
	return 3 if answered < WARMUP_QUESTIONS else 4


## Points a correct answer would earn with `time_left` seconds remaining.
func points_for(time_left: float) -> int:
	var frac := clampf(time_left / time_limit(), 0.0, 1.0)
	return (BASE_POINTS + roundi(SPEED_POINTS * frac)) * multiplier()


func answer_correct(time_left: float) -> int:
	if is_over():
		return 0
	var pts := points_for(time_left)
	score += pts
	streak += 1
	best_streak = maxi(best_streak, streak)
	correct += 1
	answered += 1
	return pts


## Wrong answer or timeout: lose a life and the streak.
func answer_wrong(sign_id := "") -> void:
	if is_over():
		return
	lives = maxi(0, lives - 1)
	streak = 0
	answered += 1
	if sign_id != "" and not missed.has(sign_id):
		missed.append(sign_id)


func timeout(sign_id := "") -> void:
	answer_wrong(sign_id)


func is_over() -> bool:
	return lives <= 0
