extends SceneTree
## Contact sheet of every sign (needs a display, not --headless):
##   godot --path . --script tools/contact_sheet.gd -- out.png [cell_px] [ids,comma,separated]
## Used to review the pictograms with a vision pass while iterating.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "contact.png"
	var cell: int = int(args[1]) if args.size() > 1 else 150
	var ids: Array = SignCatalog.ids()
	if args.size() > 2 and args[2] != "":
		ids = Array(args[2].split(","))
	var cols := 8 if ids.size() > 8 else ids.size()
	var rows := ceili(ids.size() / float(cols))
	var label_h := 26
	var w := cols * cell
	var h := rows * (cell + label_h)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var bg := ColorRect.new()
	bg.color = Color("#2b3140")
	bg.size = Vector2(w, h)
	root.add_child(bg)
	for i in ids.size():
		var v := SignView.new()
		v.shadow = false
		v.position = Vector2((i % cols) * cell, (i / cols) * (cell + label_h))
		v.size = Vector2(cell, cell)
		root.add_child(v)
		v.sign_id = ids[i]
		var l := Label.new()
		l.text = ids[i]
		l.position = v.position + Vector2(0, cell)
		l.size = Vector2(cell, label_h)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		root.add_child(l)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("contact sheet: %s %s" % [out, img.get_size()])
	quit(0)
