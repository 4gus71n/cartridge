class_name SignCatalog
extends RefCounted
## All signs in the game. Each sign has exactly one correct action, and the
## action key IS the sign id (texts: S_<ID> name, A_<ID> action,
## E_<ID> explanation in i18n/strings.csv). `pool` lists the sign ids whose
## actions make plausible wrong answers for this sign.

const CATEGORIES := ["priority", "prohibition", "mandatory", "warning", "info"]

const SIGNS := [
	# --- priority -----------------------------------------------------------
	{"id": "stop", "cat": "priority", "pool": ["give_way", "no_entry", "no_stopping", "priority_road", "road_closed"]},
	{"id": "give_way", "cat": "priority", "pool": ["stop", "priority_road", "yield_oncoming", "roundabout_ahead", "end_priority"]},
	{"id": "priority_road", "cat": "priority", "pool": ["give_way", "end_priority", "priority_junction", "priority_over_oncoming", "stop"]},
	{"id": "end_priority", "cat": "priority", "pool": ["priority_road", "end_restrictions", "give_way", "dead_end"]},
	{"id": "yield_oncoming", "cat": "priority", "pool": ["priority_over_oncoming", "two_way", "road_narrows", "no_overtaking", "give_way"]},
	{"id": "priority_over_oncoming", "cat": "priority", "pool": ["yield_oncoming", "one_way", "priority_road", "two_way"]},
	# --- prohibition --------------------------------------------------------
	{"id": "no_entry", "cat": "prohibition", "pool": ["road_closed", "one_way", "dead_end", "stop", "no_stopping"]},
	{"id": "road_closed", "cat": "prohibition", "pool": ["no_entry", "end_restrictions", "no_stopping", "no_parking", "dead_end"]},
	{"id": "speed_30", "cat": "prohibition", "pool": ["speed_60", "min_speed_30", "children", "end_speed_60", "speed_90"]},
	{"id": "speed_60", "cat": "prohibition", "pool": ["speed_30", "speed_90", "end_speed_60", "min_speed_30"]},
	{"id": "speed_90", "cat": "prohibition", "pool": ["speed_60", "speed_30", "end_speed_60", "end_restrictions"]},
	{"id": "end_speed_60", "cat": "prohibition", "pool": ["speed_60", "end_restrictions", "min_speed_30", "speed_90"]},
	{"id": "no_overtaking", "cat": "prohibition", "pool": ["end_no_overtaking", "two_way", "yield_oncoming", "no_trucks", "road_narrows"]},
	{"id": "end_no_overtaking", "cat": "prohibition", "pool": ["no_overtaking", "end_restrictions", "end_speed_60", "two_way"]},
	{"id": "no_left_turn", "cat": "prohibition", "pool": ["turn_left_only", "no_right_turn", "no_u_turn", "turn_right_only"]},
	{"id": "no_right_turn", "cat": "prohibition", "pool": ["turn_right_only", "no_left_turn", "no_u_turn", "turn_left_only"]},
	{"id": "no_u_turn", "cat": "prohibition", "pool": ["no_left_turn", "roundabout", "no_right_turn", "dead_end", "no_entry"]},
	{"id": "no_parking", "cat": "prohibition", "pool": ["no_stopping", "parking", "road_closed", "no_entry"]},
	{"id": "no_stopping", "cat": "prohibition", "pool": ["no_parking", "stop", "parking", "road_closed"]},
	{"id": "no_pedestrians", "cat": "prohibition", "pool": ["footpath", "ped_crossing", "ped_crossing_ahead", "children"]},
	{"id": "no_bicycles", "cat": "prohibition", "pool": ["cycle_path", "cyclists_ahead", "no_pedestrians", "road_closed"]},
	{"id": "no_trucks", "cat": "prohibition", "pool": ["weight_limit", "height_limit", "no_overtaking", "road_closed"]},
	{"id": "no_horn", "cat": "prohibition", "pool": ["no_stopping", "speed_30", "no_entry", "danger"]},
	{"id": "weight_limit", "cat": "prohibition", "pool": ["height_limit", "no_trucks", "speed_30", "steep_descent"]},
	{"id": "height_limit", "cat": "prohibition", "pool": ["weight_limit", "no_trucks", "road_narrows", "falling_rocks"]},
	{"id": "end_restrictions", "cat": "prohibition", "pool": ["end_no_overtaking", "end_speed_60", "end_priority", "road_closed"]},
	# --- mandatory ----------------------------------------------------------
	{"id": "ahead_only", "cat": "mandatory", "pool": ["one_way", "turn_right_only", "keep_right", "two_way", "no_u_turn"]},
	{"id": "turn_right_only", "cat": "mandatory", "pool": ["no_right_turn", "turn_left_only", "keep_right", "curve_right"]},
	{"id": "turn_left_only", "cat": "mandatory", "pool": ["no_left_turn", "turn_right_only", "curve_left", "ahead_only"]},
	{"id": "keep_right", "cat": "mandatory", "pool": ["turn_right_only", "curve_right", "road_narrows", "ahead_only"]},
	{"id": "roundabout", "cat": "mandatory", "pool": ["roundabout_ahead", "no_u_turn", "keep_right", "give_way"]},
	{"id": "min_speed_30", "cat": "mandatory", "pool": ["speed_30", "end_speed_60", "speed_60", "end_restrictions"]},
	{"id": "cycle_path", "cat": "mandatory", "pool": ["no_bicycles", "cyclists_ahead", "footpath", "no_pedestrians"]},
	{"id": "footpath", "cat": "mandatory", "pool": ["no_pedestrians", "ped_crossing", "ped_crossing_ahead", "cycle_path"]},
	# --- warning ------------------------------------------------------------
	{"id": "danger", "cat": "warning", "pool": ["roadworks", "slippery", "stop", "traffic_lights"]},
	{"id": "crossroads", "cat": "warning", "pool": ["priority_junction", "give_way", "traffic_lights", "roundabout_ahead"]},
	{"id": "priority_junction", "cat": "warning", "pool": ["crossroads", "priority_road", "give_way", "stop"]},
	{"id": "curve_right", "cat": "warning", "pool": ["curve_left", "double_curve", "turn_right_only", "keep_right"]},
	{"id": "curve_left", "cat": "warning", "pool": ["curve_right", "double_curve", "turn_left_only", "no_left_turn"]},
	{"id": "double_curve", "cat": "warning", "pool": ["curve_left", "curve_right", "slippery", "road_narrows"]},
	{"id": "ped_crossing_ahead", "cat": "warning", "pool": ["ped_crossing", "children", "no_pedestrians", "footpath"]},
	{"id": "children", "cat": "warning", "pool": ["ped_crossing_ahead", "speed_30", "no_pedestrians", "ped_crossing"]},
	{"id": "cyclists_ahead", "cat": "warning", "pool": ["cycle_path", "no_bicycles", "children", "ped_crossing_ahead"]},
	{"id": "roadworks", "cat": "warning", "pool": ["danger", "road_narrows", "falling_rocks", "slippery"]},
	{"id": "slippery", "cat": "warning", "pool": ["double_curve", "roadworks", "danger", "bump"]},
	{"id": "traffic_lights", "cat": "warning", "pool": ["stop", "crossroads", "ped_crossing_ahead", "level_crossing"]},
	{"id": "level_crossing", "cat": "warning", "pool": ["traffic_lights", "stop", "crossroads", "danger"]},
	{"id": "cattle", "cat": "warning", "pool": ["children", "falling_rocks", "danger", "cyclists_ahead"]},
	{"id": "falling_rocks", "cat": "warning", "pool": ["steep_descent", "roadworks", "cattle", "danger"]},
	{"id": "road_narrows", "cat": "warning", "pool": ["two_way", "yield_oncoming", "keep_right", "roadworks"]},
	{"id": "two_way", "cat": "warning", "pool": ["one_way", "road_narrows", "yield_oncoming", "end_no_overtaking"]},
	{"id": "roundabout_ahead", "cat": "warning", "pool": ["roundabout", "give_way", "crossroads", "traffic_lights"]},
	{"id": "bump", "cat": "warning", "pool": ["slippery", "steep_descent", "roadworks", "speed_30"]},
	{"id": "steep_descent", "cat": "warning", "pool": ["bump", "falling_rocks", "slippery", "weight_limit"]},
	# --- information --------------------------------------------------------
	{"id": "one_way", "cat": "info", "pool": ["no_entry", "ahead_only", "two_way", "priority_over_oncoming"]},
	{"id": "ped_crossing", "cat": "info", "pool": ["ped_crossing_ahead", "footpath", "no_pedestrians", "children"]},
	{"id": "dead_end", "cat": "info", "pool": ["no_entry", "road_closed", "one_way", "no_u_turn"]},
	{"id": "parking", "cat": "info", "pool": ["no_parking", "no_stopping", "dead_end", "end_restrictions"]},
]

static var _index := {}


static func count() -> int:
	return SIGNS.size()


static func ids() -> Array[String]:
	var out: Array[String] = []
	for s in SIGNS:
		out.append(s.id)
	return out


static func get_sign(id: String) -> Dictionary:
	if _index.is_empty():
		for i in SIGNS.size():
			_index[SIGNS[i].id] = i
	return SIGNS[_index[id]] if _index.has(id) else {}


static func has_sign(id: String) -> bool:
	return not get_sign(id).is_empty()


static func by_category(cat: String) -> Array[String]:
	var out: Array[String] = []
	for s in SIGNS:
		if s.cat == cat:
			out.append(s.id)
	return out


static func index_of(id: String) -> int:
	get_sign(id)
	return _index.get(id, -1)


## Translation keys for a sign.
static func name_key(id: String) -> String:
	return "S_" + id.to_upper()


static func action_key(id: String) -> String:
	return "A_" + id.to_upper()


static func explain_key(id: String) -> String:
	return "E_" + id.to_upper()
