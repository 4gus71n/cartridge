extends SceneTree
## Contact sheets for the photo review pass (headless OK):
##   godot --headless --path . --script tools/contact_sheet.gd -- <webp_dir> <out_prefix> [cols] [rows]
## Writes <out_prefix>_<n>.png grids with a big index number on every tile
## and <out_prefix>.txt mapping index -> file id.

const TILE := Vector2i(300, 200)
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var prefix: String = args[1]
	var cols := int(args[2]) if args.size() > 2 else 5
	var rows := int(args[3]) if args.size() > 3 else 5
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".webp"):
			files.append(f)
	files.sort()
	var per := cols * rows
	var mapping := ""
	for s in ceili(files.size() / float(per)):
		var sheet := Image.create(cols * TILE.x, rows * TILE.y, false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.05, 0.05, 0.08))
		for k in per:
			var i := s * per + k
			if i >= files.size():
				break
			var img := Image.load_from_file(dir.path_join(files[i]))
			if img == null:
				continue
			img.convert(Image.FORMAT_RGB8)
			var sc := minf(float(TILE.x - 4) / img.get_width(), float(TILE.y - 4) / img.get_height())
			img.resize(int(img.get_width() * sc), int(img.get_height() * sc), Image.INTERPOLATE_BILINEAR)
			var at := Vector2i((k % cols) * TILE.x + 2, (k / cols) * TILE.y + 2)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			_number(sheet, i, at + Vector2i(4, 4))
			mapping += "%d %s\n" % [i, files[i].get_basename()]
		sheet.save_png("%s_%d.png" % [prefix, s])
	var fa := FileAccess.open(prefix + ".txt", FileAccess.WRITE)
	fa.store_string(mapping)
	print("sheets: ", ceili(files.size() / float(per)), " files: ", files.size())
	quit(0)


func _number(img: Image, n: int, at: Vector2i) -> void:
	var s := str(n)
	var px := 5
	img.fill_rect(Rect2i(at, Vector2i(s.length() * 4 * px + px, 7 * px)), Color(0, 0, 0))
	for ci in s.length():
		var g: String = DIGITS[int(s[ci])]
		for y in 5:
			for x in 3:
				if g[y * 3 + x] == "1":
					img.fill_rect(Rect2i(at + Vector2i(px + (ci * 4 + x) * px, px + y * px), Vector2i(px, px)), Color(1, 0.85, 0.2))
