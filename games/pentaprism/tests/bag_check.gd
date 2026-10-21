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
	_state_round_trip()
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
		for i in 10:
			var p := bag.next_pair()
			check(p[0] != p[1], "pair hues differ")
			pairs[[mini(p[0], p[1]), maxi(p[0], p[1])]] = true
		check(pairs.size() == 10, "all 10 hue pairs once per pair-bag")
		var monos := {}
		for i in 5:
			monos[bag.next_mono()] = true
		check(monos.size() == 5, "all 5 pure hues once per mono-bag")


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
	check(hue_count.size() == Pieces.COLORS, "all five hues appear")
	check(float(hi) / lo < 1.15, "hues balanced within 15%% (%d..%d)" % [lo, hi])


func _state_round_trip() -> void:
	# A bag restored from to_dict() deals exactly the same continuation.
	var a := Pieces.Bag.new(4242)
	for i in 23:
		a.next_piece()
	var b := Pieces.Bag.new(1)
	b.from_dict(a.to_dict())
	var same := true
	for i in 120:
		var pa := a.next_piece()
		var pb := b.next_piece()
		same = same and pa.shape == pb.shape and pa.colors == pb.colors
	check(same, "restored bag continues identically")
	var c := Pieces.Bag.new(3)
	c.from_dict({"shapes": ["Q", 7], "pairs": [[1], "x"], "monos": [99]})
	var p := c.next_piece()
	check(p != null and Pieces.SHAPES.has(p.shape), "garbage bag state is sanitised")
	var piece := Pieces.make("W", [2, 5])
	piece.cells = piece.rotated_cells(1)
	var back := Pieces.Piece.from_dict(piece.to_dict())
	check(back != null and back.cells == piece.cells and back.colors == piece.colors, "piece dict round trip")
	check(Pieces.Piece.from_dict({"shape": "W", "cells": [[0, 0]], "colors": [1]}) == null, "malformed piece rejected")
	check(Pieces.Piece.from_dict("nope") == null, "non-dict piece rejected")
