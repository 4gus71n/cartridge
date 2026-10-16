extends SceneTree
func _initialize() -> void:
	for i in Levels.count():
		var lvl: Dictionary = Levels.get_level(i)
		if lvl.form == "free":
			continue
		var ps := Forms.params_for(lvl)
		var grids := []
		for p in ps:
			var g := []
			if p.locked:
				g = [p.init]
			else:
				var v: float = p.min
				while v <= p.max + 1e-9:
					g.append(v); v += p.step
			grids.append(g)
		var total := 1
		for g in grids: total *= g.size()
		var sols := []
		var idx := []
		idx.resize(grids.size()); idx.fill(0)
		var n := 0
		while true:
			var vals := {}
			for k in grids.size(): vals[ps[k].name] = grids[k][idx[k]]
			# cheap prefilter: targets
			var e := MathExpr.parse(Forms.expr(lvl.form, vals))
			var ok := true
			for t in lvl.targets:
				var y := e.eval(t[0])
				if absf(y - t[1]) > 3.0: ok = false; break
			if ok and Flight.simulate(e, lvl).success:
				sols.append(Forms.pretty(lvl.form, vals))
			var k := 0
			while k < grids.size():
				idx[k] += 1
				if idx[k] < grids[k].size(): break
				idx[k] = 0; k += 1
			if k == grids.size(): break
		print(i + 1, " ", lvl.form, " combos=", total, " solutions=", sols.size(), " ", sols.slice(0, 4))
	quit()
