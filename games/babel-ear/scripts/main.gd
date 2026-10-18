extends Control
## Babel Ear: one screen script for menu, rounds, reveal, summary, credits.
## Logic lives in plain classes (BabelGame, ClipBank) so tests can drive it;
## the UI bot calls the same entry points the buttons use (start_game,
## play_clip, choose, next_round, pause, save_and_exit, resume_game, ...).

enum Phase { MENU, LISTEN, REVEAL, SUMMARY, CREDITS }

const BG := Color("#0d0b1e")
const BG_BOTTOM := Color("#0a2a2b")
const PANEL := Color("#1a1838")
const CARD := Color("#141230")
const ACCENT := Color("#38d9c0")
const ACCENT2 := Color("#8f7bff")
const ON_ACCENT := Color("#04201c")
const TEXT := Color("#eef0f8")
const MUTED := Color("#9a98b8")
const GOOD := Color("#3ddc84")
const BAD := Color("#ff5d73")
const GOLD := Color("#ffd166")
const WAVE_H := 210
const PLAY_SIDE := 156

var phase := Phase.MENU
var bank: ClipBank
var game: BabelGame
var last_result := {}
var record := false
var heard_current := false     # the current clip has been started at least once
var audio_unlocked := false    # a user tap has started audio (web gesture rule)
var playing := false

var _player: AudioStreamPlayer
var _play_start_ms := 0
var _clip_len := 6.0
var _menu: Control
var _game: Control
var _summary: Control
var _credits: Control
var _overlay: Control
var _round_label: Label
var _score_label: Label
var _streak_label: Label
var _prompt: Label
var _hint: Label
var _wave: WaveformView
var _play_btn: RoundButton
var _bottom: VBoxContainer
var _choice_buttons := {}      # code -> Button
var _shown_score := 0.0
var _score_tween: Tween


func _ready() -> void:
	theme = _build_theme()
	_add_background()
	bank = ClipBank.load_default()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	show_menu()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if game != null and not game.is_over() and phase in [Phase.LISTEN, Phase.REVEAL]:
			Settings.save_game(game.to_dict())


func _process(_delta: float) -> void:
	if not playing:
		return
	var t := (Time.get_ticks_msec() - _play_start_ms) / 1000.0
	if _player.playing and _player.get_playback_position() > 0.0:
		t = _player.get_playback_position()
	if is_instance_valid(_wave):
		_wave.progress = t / _clip_len
	if t >= _clip_len + 0.05:
		_finish_playback()


func _add_background() -> void:
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, BG)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _clear_screens() -> void:
	_close_overlay()
	stop_clip()
	for c in [_menu, _game, _summary, _credits]:
		if is_instance_valid(c):
			c.queue_free()
	_menu = null
	_game = null
	_summary = null
	_credits = null
	_wave = null
	_play_btn = null
	_choice_buttons = {}


# --- menu -------------------------------------------------------------------

func has_resume() -> bool:
	if Settings.saved_game.is_empty():
		return false
	var g := BabelGame.from_dict(Settings.saved_game, bank)
	return g != null and not g.is_over()


func show_menu() -> void:
	_clear_screens()
	phase = Phase.MENU
	game = null
	_menu = _margin()
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)

	var art := EarArt.new()
	art.custom_minimum_size = Vector2(0, 340)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(art)
	box.add_child(_label(tr("TITLE"), 64, ACCENT))
	box.add_child(_wrap(_label(tr("SUBTITLE"), 30, TEXT)))
	box.add_child(_wrap(_label(tr("HOW"), 22, MUTED)))
	box.add_child(_label(tr("LANGS_COUNT") % [bank.playable.size(), bank.voices()], 22, Color(ACCENT2, 0.95)))
	box.add_child(_spacer(4))

	if has_resume():
		var g := BabelGame.from_dict(Settings.saved_game, bank)
		var res := _accent_button(tr("RESUME") % [g.round_index() + 1, BabelGame.ROUNDS], resume_game)
		res.name = "Resume"
		box.add_child(res)
	var easy := _mode_button(BabelGame.EASY, not has_resume())
	easy.name = "Easy"
	box.add_child(easy)
	var hard := _mode_button(BabelGame.HARD, false)
	hard.name = "Hard"
	box.add_child(hard)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lang := _panel_button(tr("LANGUAGE"), toggle_language)
	lang.name = "Language"
	lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lang)
	var cr := _panel_button(tr("CREDITS"), show_credits)
	cr.name = "Credits"
	cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cr)
	box.add_child(row)


func _mode_button(m: int, accent: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 116)
	b.focus_mode = Control.FOCUS_NONE
	if accent:
		_style_accent(b)
	b.pressed.connect(start_game.bind(m))
	var fg := ON_ACCENT if accent else TEXT
	var sub := ON_ACCENT if accent else MUTED
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key: String = BabelGame.MODE_KEYS[m]
	v.add_child(_label(tr("EASY" if m == BabelGame.EASY else "HARD"), 34, fg))
	var best := Settings.best_for(key)
	var line := tr("EASY_DESC" if m == BabelGame.EASY else "HARD_DESC") + "  ·  " + \
		(tr("BEST") % _fmt(best) if best > 0 else tr("NO_BEST"))
	v.add_child(_label(line, 21, sub))
	b.add_child(v)
	return b


func toggle_language() -> void:
	Settings.set_language("en" if Settings.language == "es" else "es")
	show_menu()


# --- rounds -----------------------------------------------------------------

func start_game(m: int = BabelGame.EASY, seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ (Time.get_ticks_usec() & 0xffffff)
	game = BabelGame.create(bank, m, seed_value, Settings.recent)
	Settings.mark_heard(game.clip_ids)
	Settings.save_game(game.to_dict())
	_build_game()


func resume_game() -> void:
	var g := BabelGame.from_dict(Settings.saved_game, bank)
	if g == null or g.is_over():
		start_game()
		return
	game = g
	_build_game()


func _build_game() -> void:
	_clear_screens()
	_game = _margin()
	add_child(_game)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_game.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var menu := RoundButton.new("menu", 88)
	menu.name = "Pause"
	menu.fill = PANEL
	menu.icon_color = TEXT
	menu.pressed.connect(pause)
	top.add_child(menu)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	_round_label = _label("", 26, TEXT)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(_round_label)
	_streak_label = _label("", 22, GOLD)
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(_streak_label)
	top.add_child(mid)
	_score_label = _label("0", 46, ACCENT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_score_label)
	box.add_child(top)

	var card := _rounded_frame(CARD)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(card)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 14)
	card.add_child(cv)
	_prompt = _label(tr("WHICH"), 30, TEXT)
	cv.add_child(_prompt)
	_wave = WaveformView.new()
	_wave.custom_minimum_size = Vector2(0, WAVE_H)
	_wave.accent = ACCENT
	cv.add_child(_wave)
	var center := CenterContainer.new()
	_play_btn = RoundButton.new("play", PLAY_SIDE)
	_play_btn.name = "Play"
	_play_btn.fill = ACCENT
	_play_btn.icon_color = ON_ACCENT
	_play_btn.pressed.connect(_on_play_pressed)
	center.add_child(_play_btn)
	cv.add_child(center)
	_hint = _label("", 22, MUTED)
	cv.add_child(_hint)

	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 12)
	box.add_child(_bottom)
	_shown_score = game.score
	_begin_round()


func _begin_round() -> void:
	phase = Phase.LISTEN
	stop_clip()
	heard_current = false
	last_result = {}
	var id := game.current_clip()
	var clip: Dictionary = bank.by_id[id]
	_clip_len = maxf(1.0, float(clip.get("duration", 6.0)))
	_wave.peaks = clip.get("peaks", [])
	_wave.progress = 0.0
	_round_label.text = tr("ROUND") % [game.round_index() + 1, BabelGame.ROUNDS]
	_update_streak()
	_score_label.text = _fmt(game.score)
	_prompt.text = tr("WHICH")
	_prompt.add_theme_color_override("font_color", TEXT)
	_wave.custom_minimum_size.y = WAVE_H
	_play_btn.custom_minimum_size = Vector2(PLAY_SIDE, PLAY_SIDE)
	_hint.visible = true
	_play_btn.kind = "play"
	_play_btn.pulse = not audio_unlocked
	_hint.text = tr("TAP_LISTEN") if not audio_unlocked else tr("LISTENING")
	for c in _bottom.get_children():
		c.queue_free()
	_choice_buttons = {}
	var grid := GridContainer.new()
	grid.name = "Choices"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var opts: Array = game.current_choices()
	var h := 140 if opts.size() <= 4 else 112
	for code in opts:
		var b := Button.new()
		b.text = bank.name_of(code)
		b.custom_minimum_size = Vector2(0, h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 30)
		b.clip_text = true
		b.pressed.connect(choose.bind(code))
		grid.add_child(b)
		_choice_buttons[code] = b
	_bottom.add_child(grid)
	_set_choices_enabled(audio_unlocked)
	if audio_unlocked:
		play_clip()   # later rounds start from the "Next" tap (a user gesture)


func _update_streak() -> void:
	if game.streak >= 2:
		_streak_label.text = tr("STREAK") % BabelGame.multiplier_for(game.streak)
	else:
		_streak_label.text = tr("MODE_EASY") if game.mode == BabelGame.EASY else tr("MODE_HARD")
	_streak_label.add_theme_color_override("font_color", GOLD if game.streak >= 2 else MUTED)


func _set_choices_enabled(on: bool) -> void:
	for code in _choice_buttons:
		var b: Button = _choice_buttons[code]
		b.disabled = not on
		b.modulate.a = 1.0 if on else 0.45


func _on_play_pressed() -> void:
	if playing:
		stop_clip()
	else:
		play_clip()


## Starts (or restarts) the current clip. Must be reached from a tap the first
## time (web audio unlock).
func play_clip() -> void:
	if game == null or game.is_over():
		return
	var stream := bank.stream_for(game.current_clip())
	audio_unlocked = true
	heard_current = true
	_player.stream = stream
	if stream != null:
		_player.play()
	playing = true
	_play_start_ms = Time.get_ticks_msec()
	if is_instance_valid(_play_btn):
		_play_btn.kind = "stop"
		_play_btn.pulse = false
	if phase == Phase.LISTEN:
		_hint.text = tr("LISTENING")
		_set_choices_enabled(true)


func stop_clip() -> void:
	if is_instance_valid(_player):
		_player.stop()
	if playing:
		_finish_playback()


func _finish_playback() -> void:
	playing = false
	if is_instance_valid(_player):
		_player.stop()
	if is_instance_valid(_wave):
		_wave.progress = 1.0 if heard_current else 0.0
	if is_instance_valid(_play_btn):
		_play_btn.kind = "replay"
	if phase == Phase.LISTEN and is_instance_valid(_hint):
		_hint.text = tr("REPLAY_HINT")


## Answer the current round with a language code.
func choose(code: String) -> void:
	if phase != Phase.LISTEN or game == null or game.is_over() or not heard_current:
		return
	last_result = game.answer(code, bank)
	phase = Phase.REVEAL
	if game.is_over():
		Settings.save_game({})
	else:
		Settings.save_game(game.to_dict())
	for c in _choice_buttons:
		var b: Button = _choice_buttons[c]
		b.disabled = true
		b.modulate.a = 1.0
	_show_reveal(last_result)


func _show_reveal(r: Dictionary) -> void:
	var truth: String = r["truth"]
	var clip: Dictionary = bank.by_id[game.clip_ids[game.round_index() - 1]]
	var ok: bool = r["correct"]
	_prompt.text = tr("CORRECT") if ok else tr("WRONG")
	_prompt.add_theme_color_override("font_color", GOOD if ok else BAD)
	_hint.visible = false
	_wave.custom_minimum_size.y = 170
	_play_btn.custom_minimum_size = Vector2(128, 128)
	_update_streak()
	_animate_score(game.score)
	for c in _bottom.get_children():
		c.queue_free()
	var card := _rounded_frame(PANEL)
	card.name = "Reveal"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var name_l := _label(bank.name_of(truth), 46, ACCENT)
	name_l.name = "LangName"
	v.add_child(name_l)
	var pts_text := tr("WRONG_DETAIL") % bank.name_of(r["picked"])
	if ok:
		pts_text = tr("POINTS_MULT") % [r["points"], r["multiplier"]] if r["multiplier"] > 1 else tr("POINTS") % r["points"]
	v.add_child(_label(pts_text, 26, GOLD if ok else BAD))
	v.add_child(_spacer(2))
	var where := _wrap(_label(tr("SPOKEN_IN") + ": " + bank.where_of(truth), 23, TEXT))
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(where)
	var fact := _wrap(_label(bank.fact_of(truth), 23, TEXT.darkened(0.12)))
	fact.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(fact)
	var src := _wrap(_label(source_text(clip), 21, MUTED))
	src.name = "Source"
	src.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(src)
	_bottom.add_child(card)
	var next := _accent_button(tr("SEE_RESULTS") if game.is_over() else tr("NEXT"), next_round)
	next.name = "Next"
	_bottom.add_child(next)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.22)
	if ok:
		var pop := create_tween()
		_score_label.pivot_offset = _score_label.size * Vector2(1.0, 0.5)
		pop.tween_property(_score_label, "scale", Vector2(1.18, 1.18), 0.1)
		pop.tween_property(_score_label, "scale", Vector2.ONE, 0.18)


func source_text(clip: Dictionary) -> String:
	var book := str(clip.get("book_display", clip.get("book", "")))
	var author := str(clip.get("author_display", ""))
	if author != "" and author != "Various":
		book += " (" + author + ")"
	return tr("SOURCE_LINE") % [book, str(clip.get("reader_display", clip.get("reader", "")))]


func next_round() -> void:
	if game == null:
		return
	if game.is_over():
		show_summary()
		return
	_begin_round()


func _animate_score(target: int) -> void:
	if _score_tween:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(func(v: float) -> void:
		_shown_score = v
		if is_instance_valid(_score_label):
			_score_label.text = _fmt(int(round(v))), _shown_score, float(target), 0.45)


# --- pause ------------------------------------------------------------------

func pause() -> void:
	if phase not in [Phase.LISTEN, Phase.REVEAL] or has_overlay():
		return
	stop_clip()
	var v := _overlay_panel()
	v.add_child(_label(tr("PAUSED"), 44, ACCENT))
	v.add_child(_spacer(8))
	var cont := _accent_button(tr("CONTINUE"), _close_overlay)
	cont.name = "Continue"
	v.add_child(cont)
	var se := _panel_button(tr("SAVE_EXIT"), save_and_exit)
	se.name = "SaveExit"
	v.add_child(se)
	var q := _panel_button(tr("QUIT_GAME"), abandon_game)
	q.name = "Abandon"
	v.add_child(q)


func save_and_exit() -> void:
	if game != null and not game.is_over():
		Settings.save_game(game.to_dict())
	show_menu()


func abandon_game() -> void:
	Settings.save_game({})
	show_menu()


# --- summary ----------------------------------------------------------------

func show_summary() -> void:
	var g := game
	_clear_screens()
	game = g
	phase = Phase.SUMMARY
	record = Settings.submit_score(game.mode_key(), game.score)
	_summary = _margin()
	add_child(_summary)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_summary.add_child(box)
	box.add_child(_label(tr("FINAL_SCORE"), 28, MUTED))
	var sc := _label(_fmt(game.score), 92, ACCENT)
	sc.name = "FinalScore"
	box.add_child(sc)
	var rec := _label(tr("NEW_BEST") if record else tr("BEST") % _fmt(Settings.best_for(game.mode_key())), 30, GOLD if record else MUTED)
	rec.name = "Record"
	box.add_child(rec)
	box.add_child(_label(tr("RESULT_LINE") % [game.correct_count(bank), BabelGame.ROUNDS, game.best_streak], 24, TEXT))
	var card := _rounded_frame(CARD)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(card)
	var list := VBoxContainer.new()
	list.name = "Rounds"
	list.add_theme_constant_override("separation", 10)
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(list)
	for i in BabelGame.ROUNDS:
		var truth := game.truth_of(i, bank)
		var ok := game.answers[i] == truth
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(18, 18)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = GOOD if ok else BAD
		sb.set_corner_radius_all(9)
		dot.add_theme_stylebox_override("panel", sb)
		row.add_child(dot)
		var nl := _label(bank.name_of(truth), 26, TEXT)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)
		var right := ("+" + _fmt(game.points[i])) if ok else bank.name_of(game.answers[i])
		var rl := _label(right, 22, GOLD if ok else Color(BAD, 0.85))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(rl)
		list.add_child(row)
	var again := _accent_button(tr("PLAY_AGAIN"), start_game.bind(game.mode))
	again.name = "PlayAgain"
	box.add_child(again)
	var menu := _panel_button(tr("MENU"), show_menu)
	menu.name = "Menu"
	box.add_child(menu)
	sc.pivot_offset = Vector2(360, 46)
	sc.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(sc, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- credits ----------------------------------------------------------------

func show_credits() -> void:
	_clear_screens()
	phase = Phase.CREDITS
	_credits = _margin()
	add_child(_credits)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_credits.add_child(box)
	box.add_child(_label(tr("CREDITS_TITLE"), 46, ACCENT))
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var intro := _wrap(_label(tr("CREDITS_INTRO"), 22, TEXT))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	list.add_child(intro)
	var codes: Array[String] = bank.playable.duplicate()
	codes.sort_custom(func(a, b): return bank.name_of(a) < bank.name_of(b))
	for code in codes:
		list.add_child(_spacer(6))
		var h := _label(bank.name_of(code), 28, ACCENT)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(h)
		for id in bank.by_lang[code]:
			var c: Dictionary = bank.by_id[id]
			var l := _wrap(_label(tr("CREDITS_CLIP") % [id, str(c.get("book_display", "")), str(c.get("reader_display", ""))], 20, MUTED))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			list.add_child(l)
	list.add_child(_spacer(8))
	var foot := _wrap(_label("librivox.org · archive.org", 19, MUTED))
	list.add_child(foot)
	var back := _accent_button(tr("BACK"), show_menu)
	back.name = "Back"
	box.add_child(back)
	_enable_touch_scroll(scroll)


func _enable_touch_scroll(scroll: ScrollContainer) -> void:
	# Drag anywhere on the list to scroll (labels don't eat the drag).
	scroll.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventScreenDrag:
			scroll.scroll_vertical -= int(ev.relative.y)
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
			scroll.scroll_vertical -= int(ev.relative.y))


# --- overlay ----------------------------------------------------------------

func _overlay_panel() -> VBoxContainer:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	return v


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func has_overlay() -> bool:
	return is_instance_valid(_overlay)


# --- widgets ----------------------------------------------------------------

func _rounded_frame(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(color)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 30)
	m.add_theme_constant_override("margin_right", 30)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 34)
	return m


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _style_accent(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(ACCENT))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.2)))
	b.add_theme_stylebox_override("hover_pressed", _box(ACCENT.darkened(0.2)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ON_ACCENT)


func _accent_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 100)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	_style_accent(b)
	b.pressed.connect(cb)
	return b


func _panel_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	var normal := _box(PANEL)
	normal.border_color = Color(1, 1, 1, 0.09)
	normal.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", _box(PANEL.lightened(0.08)))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.55)))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT.darkened(0.55)))
	t.set_stylebox("disabled", "Button", normal)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.set_color(k, "Button", TEXT)
	var panel := _box(Color("#16143a"))
	panel.content_margin_left = 32
	panel.content_margin_right = 32
	panel.content_margin_top = 28
	panel.content_margin_bottom = 28
	panel.border_color = Color(ACCENT, 0.45)
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(1, 1, 1, 0.16)
	vs.set_corner_radius_all(4)
	vs.content_margin_left = 6
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(k, "VScrollBar", vs)
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
