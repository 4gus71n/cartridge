extends SceneTree
## Randomiser fairness: godot --headless --path . --script tests/bag_check.gd

var _pass := 0
var _fail := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_shape_bags()
	_hue_bags()
	_determinism()
	_max_drought()
	_piece_hues()
	print("bag_check: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _shape_bags() -> void:
	check(Pieces.bag_size() == 16, "bag holds 16 pieces")
	for s in [1, 2, 3, 42, 999]:
		var bag := Pieces.Bag.new(s)
		for b in 25:
			var counts := {}
			for i in Pieces.bag_size():
				var k := bag.next_shape()
				counts[k] = counts.get(k, 0) + 1
			var ok := true
			for k in Pieces.WEIGHTS:
				if counts.get(k, 0) != Pieces.WEIGHTS[k]:
					ok = false
			check(ok, "seed %d bag %d has exact shape counts %s" % [s, b, counts])


func _hue_bags() -> void:
	var bag := Pieces.Bag.new(5)
	for b in 20:
		var pairs := {}
		for i in 6:
			var p := bag.next_pair()
			check(p[0] != p[1], "pair hues differ")
			pairs[[mini(p[0], p[1]), maxi(p[0], p[1])]] = true
		check(pairs.size() == 6, "all 6 hue pairs once per pair-bag")
		var monos := {}
		for i in 4:
			monos[bag.next_mono()] = true
		check(monos.size() == 4, "all 4 pure hues once per mono-bag")


func _determinism() -> void:
	var a := Pieces.Bag.new(77)
	var b := Pieces.Bag.new(77)
	var same := true
	for i in 200:
		var pa := a.next_piece()
		var pb := b.next_piece()
		if pa.shape != pb.shape or pa.colors != pb.colors:
			same = false
	check(same, "same seed -> same sequence")
	var c := Pieces.Bag.new(78)
	var diff := false
	var a2 := Pieces.Bag.new(77)
	for i in 32:
		if a2.next_shape() != c.next_shape():
			diff = true
	check(diff, "different seed -> different sequence")


func _max_drought() -> void:
	# With a bag of 16, a shape can never be absent for more than 2*16 - 2 draws.
	var bag := Pieces.Bag.new(123)
	var last := {}
	var worst := 0
	for i in 16 * 200:
		var k := bag.next_shape()
		if last.has(k):
			worst = maxi(worst, i - last[k])
		last[k] = i
	check(worst <= 2 * 16 - 1, "max gap between same shape <= 31 (got %d)" % worst)
	check(last.size() == 14, "every shape seen")


func _piece_hues() -> void:
	var bag := Pieces.Bag.new(9)
	var hue_count := {}
	var in_range := true
	for i in 1600:
		var p := bag.next_piece()
		for h in p.colors:
			in_range = in_range and h >= 1 and h <= Pieces.COLORS
			hue_count[h] = hue_count.get(h, 0) + 1
	check(in_range, "every hue id in 1..COLORS")
	var lo := 1 << 30
	var hi := 0
	for h in hue_count:
		lo = mini(lo, hue_count[h])
		hi = maxi(hi, hue_count[h])
	check(hue_count.size() == 4, "all four hues appear")
	check(float(hi) / lo < 1.15, "hues balanced within 15%% (%d..%d)" % [lo, hi])
