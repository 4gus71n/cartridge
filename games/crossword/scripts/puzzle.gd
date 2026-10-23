class_name Puzzle
extends RefCounted
## One mini crossword: grid of solution letters ("#" = block), standard
## numbering, and the clued entries. Pure data, no scene dependency.

const ACROSS := 0
const DOWN := 1

var id := ""
## Difficulty tier this puzzle belongs to: "mini", "midi" or "big".
var tier := "mini"
var width := 0
var height := 0
## Solution per cell ("" for blocks).
var solution: Array[String] = []
## Clue number shown in each cell (0 = none).
var numbers: Array[int] = []
## Entries: {dir, number, cells: Array[int], answer, clue}
var entries: Array[Dictionary] = []
## Per cell, index into `entries` of its across / down entry (-1 = none).
var across_of: Array[int] = []
var down_of: Array[int] = []


static func from_dict(d: Dictionary) -> Puzzle:
	var p := Puzzle.new()
	p.id = str(d.get("id", ""))
	p.tier = str(d.get("tier", "mini"))
	var rows: Array = d.get("grid", [])
	p.height = rows.size()
	p.width = (rows[0] as String).length() if p.height > 0 else 0
	for r in p.height:
		var row: String = rows[r]
		for c in p.width:
			var ch := row.substr(c, 1)
			p.solution.append("" if ch == "#" else ch)
	p._number()
	var clue_sets := [d.get("across", {}), d.get("down", {})]
	for e in p.entries:
		var set_: Dictionary = clue_sets[e.dir]
		e.clue = str(set_.get(str(e.number), ""))
	return p


func is_block(i: int) -> bool:
	return solution[i] == ""


func cell_count() -> int:
	return width * height


func index(r: int, c: int) -> int:
	return r * width + c


func _white(r: int, c: int) -> bool:
	return r >= 0 and c >= 0 and r < height and c < width and not is_block(index(r, c))


func _number() -> void:
	numbers.resize(cell_count())
	numbers.fill(0)
	across_of.resize(cell_count())
	across_of.fill(-1)
	down_of.resize(cell_count())
	down_of.fill(-1)
	var across: Array[Dictionary] = []
	var down: Array[Dictionary] = []
	var n := 0
	for r in height:
		for c in width:
			if not _white(r, c):
				continue
			var starts_a := not _white(r, c - 1) and _white(r, c + 1)
			var starts_d := not _white(r - 1, c) and _white(r + 1, c)
			if not (starts_a or starts_d):
				continue
			n += 1
			numbers[index(r, c)] = n
			if starts_a:
				across.append(_entry(ACROSS, n, r, c, 0, 1))
			if starts_d:
				down.append(_entry(DOWN, n, r, c, 1, 0))
	entries.clear()
	entries.append_array(across)
	entries.append_array(down)
	for k in entries.size():
		for i in entries[k].cells:
			if entries[k].dir == ACROSS:
				across_of[i] = k
			else:
				down_of[i] = k


func _entry(dir: int, n: int, r: int, c: int, dr: int, dc: int) -> Dictionary:
	var cells: Array[int] = []
	var ans := ""
	while _white(r, c):
		cells.append(index(r, c))
		ans += solution[index(r, c)]
		r += dr
		c += dc
	return {"dir": dir, "number": n, "cells": cells, "answer": ans, "clue": ""}


func entry_at(i: int, dir: int) -> int:
	return across_of[i] if dir == ACROSS else down_of[i]


func white_cells() -> Array[int]:
	var out: Array[int] = []
	for i in cell_count():
		if not is_block(i):
			out.append(i)
	return out
