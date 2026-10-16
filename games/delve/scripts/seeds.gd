class_name Seeds
extends RefCounted
## Seed hashing. Godot's RandomNumberGenerator has no avalanche on its seed
## (seeds 1 and 2 give correlated streams), so every derived stream is seeded
## through a 32-bit integer hash (lowbias32 style) first.

const MASK := 0xFFFFFFFF


## 32x32 -> low 32 bits without overflowing GDScript's signed 64-bit ints.
static func _mul32(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK


static func hash32(x: int) -> int:
	x &= MASK
	x ^= x >> 16
	x = _mul32(x, 0x7feb352d)
	x ^= x >> 15
	x = _mul32(x, 0x846ca68b)
	x ^= x >> 16
	return x


static func mix(a: int, b: int) -> int:
	return hash32(hash32(a) ^ _mul32(b + 0x9e3779b9, 0x85ebca6b))


static func make_rng(run_seed: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = mix(run_seed, salt)
	return r


## Six-character seed code shown to the player.
static func code(run_seed: int) -> String:
	const ALPHA := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	var v := run_seed & MASK
	for i in 6:
		s += ALPHA[v % 32]
		v = v / 32
	return s
