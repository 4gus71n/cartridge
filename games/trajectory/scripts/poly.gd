class_name Poly
extends RefCounted
## Polynomial helpers for the "ideal answer" card: detect whether an
## expression is a polynomial of degree ≤ 3 and print it in standard form.


## Coefficients [c0, c1, c2, c3] of f if it is a polynomial of degree ≤ 3,
## else an empty array. Fits a cubic through 4 points, then verifies it at
## other points.
static func fit(f: MathExpr) -> PackedFloat64Array:
	if f == null or not f.ok:
		return PackedFloat64Array()
	var xs := [-1.0, 0.0, 1.0, 2.0]
	var m := []
	for x in xs:
		var y := f.eval(x)
		if not is_finite(y):
			return PackedFloat64Array()
		m.append([1.0, x, x * x, x * x * x, y])
	# Gaussian elimination with partial pivoting on the 4x5 matrix.
	for col in 4:
		var piv := col
		for r in range(col + 1, 4):
			if absf(m[r][col]) > absf(m[piv][col]):
				piv = r
		var tmp = m[col]
		m[col] = m[piv]
		m[piv] = tmp
		for r in 4:
			if r == col:
				continue
			var fac: float = m[r][col] / m[col][col]
			for c in range(col, 5):
				m[r][c] -= fac * m[col][c]
	var co := PackedFloat64Array()
	for r in 4:
		var v: float = m[r][4] / m[r][r]
		co.append(0.0 if absf(v) < 1e-9 else v)
	for x in [-7.5, -3.3, 3.0, 4.5, 8.25]:
		var want := f.eval(x)
		var got := eval_coeffs(co, x)
		if not is_finite(want) or absf(want - got) > 1e-6 * maxf(1.0, absf(want)):
			return PackedFloat64Array()
	return co


static func eval_coeffs(co: PackedFloat64Array, x: float) -> float:
	var y := 0.0
	for k in range(co.size() - 1, -1, -1):
		y = y * x + co[k]
	return y


## "0.5x² − 2x + 5" (typographic minus, coefficients rounded to 4 places).
static func format(co: PackedFloat64Array) -> String:
	var terms := []
	for k in range(co.size() - 1, -1, -1):
		var c := snappedf(co[k], 0.0001)
		if is_zero_approx(c):
			continue
		var body: String = ["", "x", "x²", "x³"][k]
		var coef := Forms.num_signed(c)
		if body != "" and is_equal_approx(c, 1.0):
			coef = ""
		elif body != "" and is_equal_approx(c, -1.0):
			coef = Forms.MINUS
		terms.append(coef + body)
	return Forms._sum(terms)
