class_name MapProjection
extends RefCounted
## Miller cylindrical projection into "map units" (top-left origin, y down)
## plus the view transform used by MapView: screen = map * zoom + offset.

const UNITS_PER_DEG := 10.0
const MAX_LAT := 90.0

## Miller y for lat (in degree-like units).
static func miller_y(lat: float) -> float:
	var phi := deg_to_rad(clampf(lat, -MAX_LAT, MAX_LAT))
	return rad_to_deg(1.25 * log(tan(PI / 4.0 + 0.4 * phi)))


static func miller_lat(y: float) -> float:
	return rad_to_deg(2.5 * atan(exp(0.8 * deg_to_rad(y))) - 0.625 * PI)


static func y_extent() -> float:
	return miller_y(MAX_LAT)


## Map size in map units.
static func map_size() -> Vector2:
	return Vector2(360.0 * UNITS_PER_DEG, 2.0 * y_extent() * UNITS_PER_DEG)


## Vector2(lon, lat) -> map units.
static func project(geo: Vector2) -> Vector2:
	return Vector2((geo.x + 180.0) * UNITS_PER_DEG, (y_extent() - miller_y(geo.y)) * UNITS_PER_DEG)


## Map units -> Vector2(lon, lat). Clamped to the valid range.
static func unproject(p: Vector2) -> Vector2:
	var lon := clampf(p.x / UNITS_PER_DEG - 180.0, -180.0, 180.0)
	var y := clampf(y_extent() - p.y / UNITS_PER_DEG, -y_extent(), y_extent())
	return Vector2(lon, miller_lat(y))


static func to_screen(geo: Vector2, zoom: float, offset: Vector2) -> Vector2:
	return project(geo) * zoom + offset


static func from_screen(screen: Vector2, zoom: float, offset: Vector2) -> Vector2:
	return unproject((screen - offset) / zoom)
