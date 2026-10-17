extends Control
## Right of Way: menu, Endless run, Learn guide and overlays, built in code
## so the whole UI is styled from one place (_build_theme). Game rules live
## in RunState / SignQuiz; this script only drives the screens.

const BG := Color("#0b0e18")
const BG_BOTTOM := Color("#1b1631")
const PANEL := Color("#1a2033")
const ACCENT := Color("#ffb703")
const ON_ACCENT := Color("#1d1400")
const TEXT := Color("#eef0f6")
const MUTED := Color("#8e94aa")
const GOOD := Color("#3ddc84")
const BAD := Color("#ff4d5a")
const GOLD := Color("#ffd166")
const CAT_COLORS := {
	"priority": Color("#ffd166"), "prohibition": Color("#ff6b6b"),
	"mandatory": Color("#5aa9ff"), "warning": Color("#ffb703"), "info": Color("#7fd1ff"),
}

const INTRO_TIME := 0.3 ## sign pop-in before the clock starts
const REVEAL_CORRECT := 0.55
const REVEAL_WRONG := 0.8
const CHOICE_H := 112

enum Phase { NONE, ASK, REVEAL, FEEDBACK, OVER }

var run: RunState
var quiz: SignQuiz
var question := {}
var phase := Phase.NONE
var paused := false
var time_left := 0.0
var time_limit := 1.0
var last_correct := false
var last_timeout := false
var last_points := 0
var record := false
var detail_ids: Array = []
var detail_index := 0

var _game_id := 0
var _intro := 0.0
var _reveal := 0.0
var _shown_score := 0.0
var _menu: Control
var _game: Control
var _learn: Control
var _overlay: Control
var _road: RoadScene
var _timer: TimerBar
var _lives: LivesView
var _score_label: Label
var _streak_label: Label
var _choices_box: VBoxContainer
var _choice_buttons: Array[Button] = []
var _feedback: PanelContainer
var _next_button: Button
var _hero_timer: Timer
var _hero_i := 0
var _swipe_from := Vector2.INF


func _ready() -> void:
	theme = _build_theme()
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, BG)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _game != null and (phase == Phase.ASK or phase == Phase.REVEAL) and not paused:
			pause()


# --- menu -------------------------------------------------------------------

func show_menu() -> void:
	_clear_screens()
	_menu = _margin()
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_menu.add_child(box)

	var hero := RoadScene.new()
	hero.custom_minimum_size = Vector2(0, 420)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.speed = 0.22
	box.add_child(hero)
	_road = hero
	var hero_ids := ["stop", "give_way", "roundabout", "children", "no_entry", "priority_road", "level_crossing", "speed_60"]
	hero.sign_view.sign_id = hero_ids[0]
	_hero_i = 0
	_hero_timer = Timer.new()
	_hero_timer.wait_time = 1.8
	_hero_timer.autostart = true
	_hero_timer.timeout.connect(func() -> void:
		_hero_i = (_hero_i + 1) % hero_ids.size()
		hero.sign_view.sign_id = hero_ids[_hero_i]
		_pop_sign(hero.sign_view))
	hero.add_child(_hero_timer)

	box.add_child(_label(tr("TITLE"), 68, ACCENT))
	var sub := _label(tr("SUBTITLE"), 26, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(_spacer(4))

	var play := _accent_button(tr("MODE_ENDLESS"), start_run)
	play.name = "Endless"
	box.add_child(play)
	box.add_child(_label(tr("MODE_ENDLESS_SUB"), 22, MUTED))
	var learn := _panel_button(tr("MODE_LEARN"), show_learn)
	learn.name = "Learn"
	box.add_child(learn)
	box.add_child(_label(tr("MODE_LEARN_SUB") % SignCatalog.count(), 22, MUTED))

	var best_text := tr("NO_BEST") if Settings.best_score <= 0 else tr("BEST") % Settings.best_score
	box.add_child(_label(best_text, 28, GOLD))

	var lang := Button.new()
	lang.text = tr("LANGUAGE")
	lang.flat = true
	lang.custom_minimum_size = Vector2(0, 88)
	lang.add_theme_color_override("font_color", ACCENT.lightened(0.25))
	lang.pressed.connect(func() -> void:
		Settings.set_language("en" if Settings.language == "es" else "es")
		show_menu())
	box.add_child(lang)


# --- endless run ------------------------------------------------------------

func start_run(seed_value: int = -1) -> void:
	_clear_screens()
	_game_id += 1
	run = RunState.new()
	quiz = SignQuiz.new(seed_value)
	paused = false
	record = false
	_shown_score = 0.0

	_game = _margin()
	_game.add_theme_constant_override("margin_top", 24)
	_game.add_theme_constant_override("margin_bottom", 24)
	add_child(_game)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_game.add_child(box)

	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 14)
	box.add_child(hud)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.name = "Pause"
	pause_btn.custom_minimum_size = Vector2(88, 88)
	pause_btn.add_theme_font_size_override("font_size", 32)
	pause_btn.pressed.connect(pause)
	hud.add_child(pause_btn)
	_score_label = _stat(hud, tr("SCORE"), 46, true)
	_streak_label = _stat(hud, tr("STREAK_CAP"), 34, false)
	_streak_label.get_parent().custom_minimum_size = Vector2(150, 0)
	_lives = LivesView.new()
	_lives.custom_minimum_size = Vector2(150, 88)
	_lives.total = RunState.START_LIVES
	_lives.lives = run.lives
	hud.add_child(_lives)

	_timer = TimerBar.new()
	_timer.custom_minimum_size = Vector2(0, 22)
	box.add_child(_timer)

	_road = RoadScene.new()
	_road.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_road.custom_minimum_size = Vector2(0, 280)
	box.add_child(_road)

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 4 * CHOICE_H + 3 * 12)
	box.add_child(bottom)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 12)
	_choices_box.alignment = BoxContainer.ALIGNMENT_END
	_choices_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.add_child(_choices_box)
	_feedback = PanelContainer.new()
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feedback.visible = false
	bottom.add_child(_feedback)

	_update_hud()
	next_question()


func next_question() -> void:
	if run == null or run.is_over():
		return
	question = quiz.next_question(run.choice_count())
	time_limit = run.time_limit()
	time_left = time_limit
	_intro = INTRO_TIME
	phase = Phase.ASK
	_road.sign_view.sign_id = question.id
	_road.sign_view.rotation = 0.0
	_road.speed = 0.3 + 0.035 * mini(run.streak, 20)
	_pop_sign(_road.sign_view)
	_feedback.visible = false
	_choices_box.visible = true
	for b in _choice_buttons:
		b.queue_free()
	_choice_buttons.clear()
	for i in question.choices.size():
		var b := Button.new()
		b.name = "Choice%d" % i
		b.text = tr(SignCatalog.action_key(question.choices[i]))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, CHOICE_H)
		b.add_theme_font_size_override("font_size", 29)
		b.pressed.connect(answer.bind(i))
		_choices_box.add_child(b)
		_choice_buttons.append(b)
		b.modulate.a = 0.0
		b.create_tween().tween_property(b, "modulate:a", 1.0, 0.16).set_delay(0.04 * i)
	_timer.frozen = false
	_timer.ratio = 1.0
	_update_hud()


## Player picked choice `i` (also the entry point for tests / keys 1-4).
func answer(i: int) -> void:
	if phase != Phase.ASK or paused or run == null:
		return
	last_timeout = false
	last_correct = i == question.answer
	_mark_choices(i)
	if last_correct:
		var old_mult := run.multiplier()
		last_points = run.answer_correct(time_left)
		_reveal = REVEAL_CORRECT
		_float_text("+%d" % last_points, GOOD, 52)
		if run.multiplier() > old_mult:
			_float_text(tr("MULT_UP") % run.multiplier(), GOLD, 40, 80.0)
		Input.vibrate_handheld(15)
	else:
		_miss()
	phase = Phase.REVEAL
	_update_hud()


func _on_timeout() -> void:
	last_timeout = true
	last_correct = false
	_mark_choices(-1)
	_miss()
	phase = Phase.REVEAL
	_update_hud()


func _miss() -> void:
	last_points = 0
	run.answer_wrong(question.id)
	quiz.mark_missed(question.id)
	_reveal = REVEAL_WRONG
	_lives.lives = run.lives
	_timer.frozen = true
	Input.vibrate_handheld(120)
	var sv := _road.sign_view
	var tw := sv.create_tween()
	for k in 4:
		tw.tween_property(sv, "rotation", 0.09 * (1 if k % 2 == 0 else -1), 0.05)
	tw.tween_property(sv, "rotation", 0.0, 0.05)


func _mark_choices(picked: int) -> void:
	for i in _choice_buttons.size():
		var b := _choice_buttons[i]
		b.disabled = true
		var col := PANEL
		if i == question.answer:
			col = GOOD.darkened(0.35)
		elif i == picked:
			col = BAD.darkened(0.3)
		else:
			b.modulate.a = 0.45
		b.add_theme_stylebox_override("disabled", _box(col))
		b.add_theme_color_override("font_disabled_color", TEXT)


func _show_feedback() -> void:
	phase = Phase.FEEDBACK
	_choices_box.visible = false
	for c in _feedback.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_feedback.add_child(box)
	var id: String = question.id
	box.add_child(_label(tr("TIMEOUT") if last_timeout else tr("WRONG"), 34, BAD))
	var name_l := _label(tr(SignCatalog.name_key(id)), 34, GOLD)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_l)
	box.add_child(_label(tr("CORRECT_ACTION"), 22, MUTED))
	var act := _label(tr(SignCatalog.action_key(id)), 28, GOOD)
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(act)
	var ex := _label(tr(SignCatalog.explain_key(id)), 25, TEXT)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ex)
	_next_button = _accent_button(tr("SEE_RESULTS") if run.is_over() else tr("NEXT"), advance)
	_next_button.name = "Next"
	box.add_child(_next_button)
	_feedback.visible = true
	_feedback.modulate.a = 0.0
	_feedback.create_tween().tween_property(_feedback, "modulate:a", 1.0, 0.18)


## "Next" after a miss: next sign, or the results when out of lives.
func advance() -> void:
	if phase != Phase.FEEDBACK or paused:
		return
	if run.is_over():
		end_run()
	else:
		next_question()


func _process(delta: float) -> void:
	if _game == null or run == null or paused:
		return
	match phase:
		Phase.ASK:
			if _intro > 0.0:
				_intro -= delta
			else:
				time_left = maxf(0.0, time_left - delta)
				if time_left <= 0.0:
					_on_timeout()
			_timer.ratio = time_left / time_limit
		Phase.REVEAL:
			_reveal -= delta
			if _reveal <= 0.0:
				if last_correct:
					next_question()
				else:
					_show_feedback()
	_update_hud(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or _game == null:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_4:
		answer(k - KEY_1)
	elif k == KEY_ENTER or k == KEY_SPACE:
		advance()
	elif k == KEY_ESCAPE or k == KEY_P:
		if paused:
			resume()
		else:
			pause()
	else:
		return
	get_viewport().set_input_as_handled()


func _update_hud(delta := 0.0) -> void:
	if run == null or _score_label == null:
		return
	if delta > 0.0:
		_shown_score = move_toward(_shown_score, run.score, maxf(60.0, (run.score - _shown_score) * 9.0) * delta)
	else:
		_shown_score = run.score
	_score_label.text = str(int(_shown_score))
	var m := run.multiplier()
	_streak_label.text = str(run.streak) if m <= 1 else "%d  ×%d" % [run.streak, m]
	_streak_label.add_theme_color_override("font_color", TEXT if m <= 1 else GOLD)
	_lives.lives = run.lives


func end_run() -> void:
	if run == null or phase == Phase.OVER:
		return
	phase = Phase.OVER
	paused = false
	record = Settings.submit_run(run.score, run.best_streak)
	_show_over()


# --- overlays ---------------------------------------------------------------

func pause() -> void:
	if run == null or _game == null or phase == Phase.OVER or _overlay != null:
		return
	paused = true
	var box := _overlay_panel()
	box.add_child(_label(tr("PAUSED"), 56, TEXT))
	box.add_child(_label(tr("POINTS") % run.score, 30, MUTED))
	box.add_child(_accent_button(tr("RESUME"), resume))
	var quit_btn := _flat(tr("QUIT_RUN"))
	quit_btn.pressed.connect(func() -> void:
		_close_overlay()
		end_run())
	box.add_child(quit_btn)
	var menu := _flat(tr("MENU"))
	menu.pressed.connect(show_menu)
	box.add_child(menu)


func resume() -> void:
	_close_overlay()
	paused = false


func _show_over() -> void:
	var box := _overlay_panel()
	box.add_child(_label(tr("GAME_OVER"), 56, ACCENT))
	var score := _label(str(run.score), 88, TEXT)
	box.add_child(score)
	if record:
		var nb := _label(tr("NEW_BEST"), 34, GOLD)
		box.add_child(nb)
		_flash(nb)
	elif Settings.best_score > 0:
		box.add_child(_label(tr("BEST") % Settings.best_score, 28, GOLD))
	var stats := _label(tr("STATS") % [run.correct, run.best_streak], 26, MUTED)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)
	box.add_child(_accent_button(tr("PLAY_AGAIN"), func() -> void: start_run()))
	if not run.missed.is_empty():
		var rev := _panel_button(tr("REVIEW"), func() -> void: review_missed())
		rev.name = "Review"
		box.add_child(rev)
	var menu := _flat(tr("MENU"))
	menu.pressed.connect(show_menu)
	box.add_child(menu)


func review_missed() -> void:
	var missed: Array = run.missed.duplicate() if run != null else []
	show_learn(missed)
	if not missed.is_empty():
		open_detail(missed, 0)


func _overlay_panel() -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	panel.pivot_offset = Vector2(300, 260)
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	return box


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func has_overlay() -> bool:
	return _overlay != null


# --- learn ------------------------------------------------------------------

## Grid of every sign by category; `marked` ids (missed in the last run) are
## highlighted and listed first.
func show_learn(marked: Array = []) -> void:
	_clear_screens()
	run = null
	phase = Phase.NONE
	_learn = _margin()
	_learn.add_theme_constant_override("margin_top", 24)
	add_child(_learn)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_learn.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var back := Button.new()
	back.text = tr("BACK")
	back.name = "Back"
	back.custom_minimum_size = Vector2(150, 88)
	back.pressed.connect(show_menu)
	head.add_child(back)
	var title := _label(tr("LEARN_TITLE"), 44, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_spacer_w(150))
	var hint := _label(tr("LEARN_HINT"), 24, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var groups: Array = []
	if not marked.is_empty():
		groups.append(["REVIEW_CAP", marked, BAD])
	for cat in SignCatalog.CATEGORIES:
		groups.append(["CAT_" + cat.to_upper(), SignCatalog.by_category(cat), CAT_COLORS[cat]])
	for g in groups:
		var cap := _label(tr(g[0]), 28, g[2])
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(cap)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		list.add_child(grid)
		var ids: Array = g[1]
		for i in ids.size():
			var t := SignTile.new(ids[i])
			t.custom_minimum_size = Vector2(0, 156)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t.marked = marked.has(ids[i])
			t.tapped.connect(func(_id: String) -> void: open_detail(ids, i))
			grid.add_child(t)
		list.add_child(_spacer(8))


## Full-screen card for ids[index] with prev/next + swipe.
func open_detail(ids: Array, index: int) -> void:
	detail_ids = ids
	detail_index = posmod(index, ids.size())
	var box := _overlay_panel()
	_overlay.gui_input.connect(_detail_swipe)
	var id: String = ids[detail_index]
	var sign := SignCatalog.get_sign(id)
	var cat := _label(tr("CAT_" + String(sign.cat).to_upper()), 24, CAT_COLORS[sign.cat])
	box.add_child(cat)
	var sv := SignView.new()
	sv.custom_minimum_size = Vector2(0, 300)
	sv.sign_id = id
	box.add_child(sv)
	var name_l := _label(tr(SignCatalog.name_key(id)), 38, TEXT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_l)
	box.add_child(_label(tr("WHAT_TO_DO"), 22, MUTED))
	var act := _label(tr(SignCatalog.action_key(id)), 29, GOOD)
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(act)
	var ex := _label(tr(SignCatalog.explain_key(id)), 25, TEXT)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ex.custom_minimum_size = Vector2(528, 0)
	box.add_child(ex)
	box.add_child(_label("%d / %d" % [detail_index + 1, ids.size()], 22, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var prev := Button.new()
	prev.text = "‹  " + tr("PREV")
	prev.name = "Prev"
	prev.custom_minimum_size = Vector2(0, 96)
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev.pressed.connect(func() -> void: open_detail(detail_ids, detail_index - 1))
	row.add_child(prev)
	var nxt := Button.new()
	nxt.text = tr("NEXT") + "  ›"
	nxt.name = "NextSign"
	nxt.custom_minimum_size = Vector2(0, 96)
	nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nxt.pressed.connect(func() -> void: open_detail(detail_ids, detail_index + 1))
	row.add_child(nxt)
	var close := _flat(tr("CLOSE"))
	close.name = "Close"
	close.pressed.connect(_close_overlay)
	box.add_child(close)


func _detail_swipe(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_swipe_from = event.position
		elif _swipe_from != Vector2.INF:
			var d: Vector2 = event.position - _swipe_from
			_swipe_from = Vector2.INF
			if absf(d.x) > 90.0 and absf(d.x) > absf(d.y) * 1.5:
				open_detail.call_deferred(detail_ids, detail_index + (1 if d.x < 0 else -1))


# --- helpers ----------------------------------------------------------------

func _clear_screens() -> void:
	for node in [_menu, _game, _learn, _overlay]:
		if is_instance_valid(node):
			node.queue_free()
	_menu = null
	_game = null
	_learn = null
	_overlay = null
	_score_label = null
	_choice_buttons.clear()
	phase = Phase.NONE
	paused = false


func _pop_sign(sv: SignView) -> void:
	sv.scale = Vector2(0.55, 0.55)
	sv.modulate.a = 0.0
	var tw := sv.create_tween().set_parallel()
	tw.tween_property(sv, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sv, "modulate:a", 1.0, 0.14)


func _float_text(t: String, col: Color, font_size: int, dy := 0.0) -> void:
	var l := _label(t, font_size, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("font_outline_size", 8)
	_road.add_child(l)
	l.size = Vector2(_road.size.x, font_size * 1.4)
	var c := _road.sign_center()
	l.position = Vector2(0, c.y - _road.sign_radius() - font_size * 0.6 + dy)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _flash(l: Control) -> void:
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(1.25, 1.25)
	l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _stat(parent: Control, caption: String, font_size: int, expand: bool) -> Label:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	if expand:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	col.add_child(_label(caption, 20, MUTED))
	var value := _label("0", font_size, TEXT)
	col.add_child(value)
	return value


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 36)
	m.add_theme_constant_override("margin_bottom", 32)
	return m


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _spacer_w(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _accent_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 108)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_stylebox_override("normal", _box(ACCENT))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.15)))
	b.add_theme_stylebox_override("hover_pressed", _box(ACCENT.darkened(0.15)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ON_ACCENT)
	b.pressed.connect(cb)
	return b


func _panel_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 100)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(func() -> void: cb.call())
	return b


func _flat(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_color_override("font_color", MUTED.lightened(0.2))
	return b


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var normal := _box(PANEL)
	normal.border_color = Color(1, 1, 1, 0.08)
	normal.set_border_width_all(2)
	var hover := _box(PANEL.lightened(0.08))
	var pressed := _box(ACCENT.darkened(0.55))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", normal)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.set_color(k, "Button", TEXT)
	var panel := _box(Color("#151a2a"))
	panel.content_margin_left = 32
	panel.content_margin_right = 32
	panel.content_margin_top = 28
	panel.content_margin_bottom = 24
	panel.border_color = Color(ACCENT, 0.45)
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(1, 1, 1, 0.16)
	vs.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", vs)
	t.set_stylebox("grabber_highlight", "VScrollBar", vs)
	t.set_stylebox("grabber_pressed", "VScrollBar", vs)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


func _box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb
