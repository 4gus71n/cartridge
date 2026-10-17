class_name WorldData
extends RefCounted
## Country polygons (Natural Earth 1:50m, simplified offline by
## tools/build_map.py). Rings are PackedVector2Array of Vector2(lon, lat).

const JSON_PATH := "res://content/world.json"
const BIN_PATH := "res://content/world.bin"

var countries: Array[Dictionary] = []   # draw order: biggest first
var by_key := {}                        # key -> country dict
var _lookup: Array[Dictionary] = []     # hit-test order: smallest first
var point_count := 0


static func load_default() -> WorldData:
	var w := WorldData.new()
	w.load_files(JSON_PATH, BIN_PATH)
	return w


func load_files(json_path: String, bin_path: String) -> bool:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var raw := FileAccess.get_file_as_bytes(bin_path)
	if typeof(meta) != TYPE_DICTIONARY or raw.is_empty():
		push_error("world data missing")
		return false
	var floats := raw.to_float32_array()
	point_count = floats.size() / 2
	for c in meta.countries:
		var rings: Array[PackedVector2Array] = []
		for r in c.rings:
			var start := int(r[0])
			var count := int(r[1])
			var ring := PackedVector2Array()
			ring.resize(count)
			for i in count:
				ring[i] = Vector2(floats[(start + i) * 2], floats[(start + i) * 2 + 1])
			rings.append(ring)
		var b: Array = c.bbox
		var country := {
			"key": String(c.k), "iso": String(c.iso), "en": String(c.en), "es": String(c.es),
			"color": int(c.c), "area": float(c.area), "rings": rings,
			"bbox": Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1]),
		}
		countries.append(country)
		by_key[country.key] = country
	_lookup = countries.duplicate()
	_lookup.sort_custom(func(a, b): return a.area < b.area)
	return true


const SNAP_KM := 30.0


## Country key (Natural Earth ADM0_A3) containing geo point, or "" for sea.
## Points within `snap_km` of a coast count for the nearest country, so a
## pin on a harbour city isn't lost to the simplified coastline.
func country_at(geo: Vector2, snap_km: float = SNAP_KM) -> String:
	for c in _lookup:
		if not c.bbox.grow(0.01).has_point(geo):
			continue
		for ring in c.rings:
			if Geometry2D.is_point_in_polygon(geo, ring):
				return c.key
	if snap_km <= 0.0:
		return ""
	var kx := cos(deg_to_rad(geo.y)) * 111.32
	var ky := 110.57
	var grow := snap_km / 100.0 / maxf(0.05, cos(deg_to_rad(geo.y)))
	var best := ""
	var best_d := snap_km
	var p := Vector2(geo.x * kx, geo.y * ky)
	for c in _lookup:
		if not c.bbox.grow(grow).has_point(geo):
			continue
		for ring: PackedVector2Array in c.rings:
			var n := ring.size()
			var prev := Vector2(ring[n - 1].x * kx, ring[n - 1].y * ky)
			for i in n:
				var cur := Vector2(ring[i].x * kx, ring[i].y * ky)
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, prev, cur))
				if d < best_d:
					best_d = d
					best = c.key
				prev = cur
	return best


func country_name(key: String, lang: String) -> String:
	if not by_key.has(key):
		return ""
	return by_key[key].es if lang == "es" else by_key[key].en


## Triangulated land for drawing, in map units, coloured by `palette[c-1]`.
## Returns {"mesh": ArrayMesh, "failed": int rings that did not triangulate}.
func build_land_mesh(palette: PackedColorArray, only_key: String = "") -> Dictionary:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var failed := 0
	for c in countries:
		if only_key != "" and c.key != only_key:
			continue
		var col: Color = palette[(int(c.color) - 1) % palette.size()]
		for ring in c.rings:
			var idx := Geometry2D.triangulate_polygon(ring)
			if idx.is_empty():
				failed += 1
				continue
			var proj := PackedVector2Array()
			proj.resize(ring.size())
			for i in ring.size():
				proj[i] = MapProjection.project(ring[i])
			for i in idx:
				verts.append(proj[i])
				cols.append(col)
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "failed": failed, "triangles": verts.size() / 3}


## Border/coast segments (pairs of points) in map units, for draw_multiline.
func border_segments() -> PackedVector2Array:
	var segs := PackedVector2Array()
	for c in countries:
		for ring in c.rings:
			var n: int = ring.size()
			var prev: Vector2 = MapProjection.project(ring[n - 1])
			for i in n:
				var p: Vector2 = MapProjection.project(ring[i])
				segs.append(prev)
				segs.append(p)
				prev = p
	return segs
