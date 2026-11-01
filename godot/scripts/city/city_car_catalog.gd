extends RefCounted
## Six additional everyday neighborhood vehicles, declared as plain data so the
## mesh kit, collision hulls, fleet distribution and tests all read one source.
## Native +Z forward, +Y up, origin on the ground at the overall length/width
## centre. Proportions are game-scale: every overall length fits the existing
## 4.70m fleet envelope (city_vehicle.gd BODY_SIZE / parked PARKING_SIZE), so
## the long sedan, pickup and van are compressed relative to their real classes.
## Original geometry; no badges, manufacturer meshes or textures.

const KINDS := ["hatchback", "midsize_sedan", "long_sedan", "pickup", "cargo_van", "compact_suv"]
const LEGACY_KINDS := ["box_sedan", "compact", "minivan"]
# Explicit developer benchmark switch only; default gameplay keeps all nine.
# Cache once so fleet selection adds no repeated command-line parsing.
static var benchmark_legacy_catalog: bool = OS.get_cmdline_user_args().has("--legacy-vehicle-catalog")
## Bumper faces stand this far proud of the lofted end caps (avoids coplanar
## z-fighting between bumper and fascia). Overall length already includes it.
const BUMPER_PROUD := 0.012
## Thirteen slots (coprime with the six-colour palette), so kind and paint never
## lock together. Slots 0-2 reproduce the legacy KINDS order for index 0..2.
const TRAFFIC_ROTATION := ["box_sedan", "compact", "minivan", "hatchback", "midsize_sedan", "pickup",
	"compact", "long_sedan", "compact_suv", "hatchback", "cargo_van", "midsize_sedan", "compact_suv"]
const PARKED_ROTATION := ["box_sedan", "compact", "minivan", "midsize_sedan", "hatchback", "long_sedan",
	"box_sedan", "compact_suv", "pickup", "compact", "midsize_sedan", "hatchback", "cargo_van"]

## Field glossary (metres):
## length/width/height  overall declared bounds (bumpers/spare included; mirrors
##                      and tyre sidewalls may add <= 0.045 per side in x)
## rear_extra           depth behind the rear bumper face (SUV tailgate spare)
## front_axle/rear_axle wheel centre z; wheel centre y == wheel_radius
## wheel_inset          wheel centre x = width/2 - wheel_inset
## sill                 rocker underside height between the arches
## deck                 [z, y] hood/beltline/trunk top profile (ascending z)
## greenhouse           [z, roof_y] stations rear->front; first/last are bases
## base_width/roof_width greenhouse half widths as fractions of width/2
## windows              side glass spans [z0, z1]; clipped to the greenhouse
## seams/handles        [z, side] door shut lines/handles; side 0 = both,
##                      -1 = -X (kerb/passenger side, see parked cars) only
## taper/droop/lift     [front, rear] plan rounding, deck roll-off, bumper lift
## height               roof top, except compact_suv whose roof rails stand
##                      15mm above its 1.685m painted roof
## shades               linear paint vertex multipliers (1 keeps the instance
##                      paint; 0.05 reads as black cladding/blackout pillars)
const DATA := {
	"hatchback": {
		"label": "Compact five-door hatchback", "era": "2000s",
		"reference": "Generic 2000s five-door compact hatchback proportions; original low-poly geometry.",
		"length": 4.06, "width": 1.74, "height": 1.48, "rear_extra": 0.0,
		"front_axle": 1.23, "rear_axle": -1.32, "wheel_radius": 0.30, "tire_half_width": 0.100, "wheel_inset": 0.075,
		"wheel_style": {"rim": "metal", "hub": "trim", "slots": "trim", "slot_count": 6},
		"sill": 0.27, "deck_round": 0.92, "arch_gap": 0.075, "rear_skirt": 0.0,
		"deck": [[-2.02, 0.90], [-1.92, 0.955], [0.95, 0.885], [1.80, 0.83], [2.02, 0.76]],
		"greenhouse": [[-1.92, 0.0], [-1.62, 1.43], [-0.70, 1.475], [0.10, 1.48], [0.95, 0.0]],
		"base_width": 0.90, "roof_width": 0.79,
		"windows": [[0.0, 0.90], [-0.92, -0.08], [-1.70, -1.00]],
		"seams": [[0.84, 0], [-0.04, 0], [-1.02, 0]], "handles": [[0.14, 0], [-0.86, 0]],
		"tall_seams": [], "taper": [0.12, 0.06], "droop": [0.06, 0.03], "lift": [0.10, 0.08],
		"accent_y": 0.47, "shades": {"under": 0.17, "rocker": 0.70, "lower": 0.88, "pillar": 1.0, "roof": 1.0, "bumper": 0.93},
		"strip": {"y": 0.60, "material": "trim"},
		"mirror": {"z": 0.80, "size": [0.06, 0.10, 0.13]},
		"front": {"lamp": [0.34, 0.11, 0.62, 0.62], "grille": [0.42, 0.08, 0.60, "trim"], "bumper": [0.32, 0.52, "paint"], "intake": [0.62, 0.07, 0.40]},
		"rear": {"lamp": [0.18, 0.20, 0.74, 0.78], "bumper": [0.32, 0.52, "paint"], "plate": [0.60, "metal"]},
		"extras": ["hatch_spoiler"]},
	"midsize_sedan": {
		"label": "Midsize four-door sedan", "era": "2000s",
		"reference": "Generic 2000s rounded midsize family sedan proportions; original low-poly geometry.",
		"length": 4.62, "width": 1.80, "height": 1.44, "rear_extra": 0.0,
		"front_axle": 1.36, "rear_axle": -1.36, "wheel_radius": 0.32, "tire_half_width": 0.105, "wheel_inset": 0.075,
		"wheel_style": {"rim": "metal", "hub": "metal", "slots": "trim", "slot_count": 5},
		"sill": 0.28, "deck_round": 0.90, "arch_gap": 0.075, "rear_skirt": 0.0,
		"deck": [[-2.30, 0.84], [-2.05, 0.95], [-1.62, 0.955], [1.30, 0.875], [2.05, 0.78], [2.30, 0.70]],
		"greenhouse": [[-1.62, 0.0], [-0.98, 1.41], [-0.35, 1.44], [0.32, 1.43], [1.30, 0.0]],
		"base_width": 0.88, "roof_width": 0.74,
		"windows": [[0.0, 1.22], [-0.90, -0.08], [-1.45, -0.98]],
		"seams": [[0.94, 0], [-0.04, 0], [-1.00, 0]], "handles": [[0.12, 0], [-0.84, 0]],
		"tall_seams": [], "taper": [0.13, 0.08], "droop": [0.06, 0.04], "lift": [0.10, 0.08],
		"accent_y": 0.46, "shades": {"under": 0.17, "rocker": 0.70, "lower": 0.88, "pillar": 0.05, "roof": 1.0, "bumper": 0.93},
		"strip": {"y": 0.56, "material": "trim"},
		"mirror": {"z": 1.12, "size": [0.06, 0.10, 0.13]},
		"front": {"lamp": [0.40, 0.11, 0.58, 0.64], "grille": [0.50, 0.07, 0.57, "trim"], "bumper": [0.32, 0.50, "paint"], "intake": [0.70, 0.07, 0.38]},
		"rear": {"lamp": [0.42, 0.11, 0.72, 0.62], "bumper": [0.32, 0.54, "paint"], "plate": [0.60, "metal"]},
		"extras": []},
	"long_sedan": {
		"label": "Older full-size long sedan", "era": "early 1990s",
		"reference": "Generic early-1990s rounded full-size rear-drive sedan (skirted rear wheels, chrome bumpers); original low-poly geometry.",
		"length": 4.64, "width": 1.94, "height": 1.42, "rear_extra": 0.0,
		"front_axle": 1.46, "rear_axle": -1.44, "wheel_radius": 0.33, "tire_half_width": 0.105, "wheel_inset": 0.080,
		"wheel_style": {"rim": "metal", "hub": "trim", "slots": "trim", "slot_count": 8},
		"sill": 0.27, "deck_round": 0.88, "arch_gap": 0.075, "rear_skirt": 0.52,
		"deck": [[-2.31, 0.80], [-2.02, 0.90], [-1.50, 0.905], [1.10, 0.86], [2.05, 0.81], [2.31, 0.74]],
		"greenhouse": [[-1.50, 0.0], [-0.98, 1.39], [-0.30, 1.42], [0.30, 1.415], [1.10, 0.0]],
		"base_width": 0.86, "roof_width": 0.71,
		"windows": [[0.02, 1.02], [-0.86, -0.06], [-1.30, -0.94]],
		"seams": [[1.06, 0], [-0.03, 0], [-1.00, 0]], "handles": [[0.14, 0], [-0.86, 0]],
		"tall_seams": [], "taper": [0.10, 0.14], "droop": [0.06, 0.08], "lift": [0.08, 0.08],
		"accent_y": 0.50, "shades": {"under": 0.17, "rocker": 0.72, "lower": 0.90, "pillar": 1.0, "roof": 0.45, "bumper": 1.0},
		"strip": {"y": 0.58, "material": "metal"},
		"mirror": {"z": 0.92, "size": [0.06, 0.09, 0.14]},
		"front": {"lamp": [0.36, 0.10, 0.58, 0.70], "grille": [0.62, 0.15, 0.56, "metal"], "bumper": [0.30, 0.47, "metal"], "intake": []},
		"rear": {"lamp": [0.50, 0.10, 0.62, 0.55], "bumper": [0.30, 0.48, "metal"], "plate": [0.545, "headlamp"]},
		"extras": ["grille_bars"]},
	"pickup": {
		"label": "Compact regular-cab pickup", "era": "1990s",
		"reference": "Generic 1990s compact regular-cab long-bed pickup proportions (two-tone lower body); original low-poly geometry.",
		"length": 4.64, "width": 1.80, "height": 1.68, "rear_extra": 0.0,
		"front_axle": 1.54, "rear_axle": -1.30, "wheel_radius": 0.355, "tire_half_width": 0.110, "wheel_inset": 0.080,
		"wheel_style": {"rim": "metal", "hub": "metal", "slots": "trim", "slot_count": 6},
		"sill": 0.40, "deck_round": 0.95, "arch_gap": 0.075, "rear_skirt": 0.0,
		"cab_back": -0.44, "bed": {"floor": 0.76, "wall": 0.065},
		"deck": [[-2.31, 1.08], [-0.44, 1.08], [1.25, 1.06], [2.15, 1.00], [2.31, 0.92]],
		"greenhouse": [[-0.44, 0.0], [-0.40, 1.68], [0.62, 1.68], [1.25, 0.0]],
		"base_width": 0.90, "roof_width": 0.82,
		"windows": [[-0.30, 1.16]],
		"seams": [[1.08, 0], [-0.36, 0]], "handles": [[-0.22, 0]],
		"tall_seams": [], "taper": [0.07, 0.0], "droop": [0.05, 0.0], "lift": [0.06, 0.04],
		"accent_y": 0.66, "shades": {"under": 0.17, "rocker": 0.30, "lower": 0.36, "pillar": 1.0, "roof": 1.0, "bumper": 1.0},
		"strip": {},
		"mirror": {"z": 1.06, "size": [0.06, 0.19, 0.14]},
		"front": {"lamp": [0.32, 0.15, 0.76, 0.66], "grille": [0.66, 0.20, 0.74, "trim"], "bumper": [0.40, 0.58, "metal"], "intake": []},
		"rear": {"lamp": [0.06, 0.28, 0.88, 1.0], "bumper": [0.42, 0.58, "metal"], "plate": [0.50, "headlamp"]},
		"extras": ["bed", "grille_surround"]},
	"cargo_van": {
		"label": "Panel cargo van", "era": "1990s-2000s",
		"reference": "Generic panel cargo van (blank cargo sides, two rear doors, kerb-side sliding door); original low-poly geometry.",
		"length": 4.62, "width": 1.96, "height": 1.98, "rear_extra": 0.0,
		"front_axle": 1.42, "rear_axle": -1.38, "wheel_radius": 0.35, "tire_half_width": 0.110, "wheel_inset": 0.080,
		"wheel_style": {"rim": "trim", "hub": "metal", "slots": "metal", "slot_count": 5},
		"sill": 0.36, "deck_round": 0.985, "arch_gap": 0.075, "rear_skirt": 0.0,
		"deck": [[-2.30, 1.10], [1.48, 1.10], [2.12, 0.99], [2.30, 0.92]],
		"greenhouse": [[-2.29, 0.0], [-2.27, 1.98], [0.80, 1.98], [1.48, 0.0]],
		"base_width": 0.965, "roof_width": 0.92,
		"windows": [[0.22, 1.40]],
		"seams": [[1.40, 0], [0.18, 0], [-0.95, -1]], "handles": [[0.30, 0], [-0.80, -1]],
		"tall_seams": [[0.18, 0], [-0.95, -1]], "taper": [0.08, 0.015], "droop": [0.04, 0.0], "lift": [0.06, 0.04],
		"accent_y": 0.55, "shades": {"under": 0.17, "rocker": 0.68, "lower": 0.85, "pillar": 1.0, "roof": 1.0, "bumper": 1.0},
		"strip": {},
		"mirror": {"z": 1.30, "size": [0.06, 0.20, 0.13]},
		"front": {"lamp": [0.30, 0.15, 0.78, 0.68], "grille": [0.80, 0.20, 0.76, "trim"], "bumper": [0.36, 0.56, "trim"], "intake": []},
		"rear": {"lamp": [0.12, 0.34, 0.86, 0.88], "bumper": [0.38, 0.56, "trim"], "plate": [0.70, "headlamp"]},
		"extras": ["rear_doors", "grille_bar"]},
	"compact_suv": {
		"label": "Compact SUV with tailgate spare", "era": "2000s",
		"reference": "Generic 2000s compact crossover SUV (black cladding, tailgate spare); original low-poly geometry.",
		"length": 4.58, "width": 1.80, "height": 1.70, "rear_extra": 0.22,
		"front_axle": 1.43, "rear_axle": -1.19, "wheel_radius": 0.345, "tire_half_width": 0.110, "wheel_inset": 0.080,
		"wheel_style": {"rim": "metal", "hub": "trim", "slots": "trim", "slot_count": 5},
		"sill": 0.36, "deck_round": 0.93, "arch_gap": 0.080, "rear_skirt": 0.0,
		"deck": [[-2.29, 1.11], [-2.06, 1.00], [-2.00, 1.035], [1.12, 1.00], [2.05, 0.92], [2.28, 0.84]],
		"greenhouse": [[-2.00, 0.0], [-1.92, 1.655], [-0.60, 1.685], [0.32, 1.685], [1.12, 0.0]],
		"base_width": 0.89, "roof_width": 0.80,
		"windows": [[0.0, 1.04], [-0.86, -0.08], [-1.86, -0.94]],
		"seams": [[1.08, 0], [-0.04, 0], [-0.90, 0]], "handles": [[0.14, 0], [-0.76, 0]],
		"tall_seams": [], "taper": [0.10, 0.05], "droop": [0.05, 0.02], "lift": [0.08, 0.06],
		"accent_y": 0.56, "shades": {"under": 0.17, "rocker": 0.05, "lower": 0.05, "pillar": 0.05, "roof": 1.0, "bumper": 1.0},
		"strip": {},
		"mirror": {"z": 0.94, "size": [0.06, 0.11, 0.14]},
		"front": {"lamp": [0.36, 0.13, 0.70, 0.64], "grille": [0.52, 0.12, 0.69, "trim"], "bumper": [0.36, 0.56, "trim"], "intake": []},
		"rear": {"lamp": [0.14, 0.24, 0.84, 0.86], "bumper": [0.36, 0.54, "trim"], "plate": [0.46, "headlamp"]},
		"extras": ["roof_rails", "spare"]},
}
static var _collision_cache: Dictionary = {}

static func has_kind(kind: String) -> bool:
	return DATA.has(kind)

static func config(kind: String) -> Dictionary:
	return DATA[kind]

static func dimensions(kind: String) -> Vector3:
	var c: Dictionary = DATA[kind]
	return Vector3(float(c.width), float(c.height), float(c.length))

static func wheel_radius(kind: String) -> float:
	return float(DATA[kind].wheel_radius)

static func reference_description(kind: String) -> String:
	return str(DATA[kind].reference)

static func label(kind: String) -> String:
	return str(DATA[kind].label)

## Lofted body ends (the bumper faces stand BUMPER_PROUD further out).
static func body_front(kind: String) -> float:
	return float(DATA[kind].length) * 0.5 - BUMPER_PROUD

static func body_rear(kind: String) -> float:
	var c: Dictionary = DATA[kind]
	return -float(c.length) * 0.5 + BUMPER_PROUD + float(c.rear_extra)

## Same order and naming contract as the legacy prototypes:
## [WheelFL, WheelRL, WheelFR, WheelRR] = [(-X, front), (-X, rear), (+X, front), (+X, rear)].
static func wheel_poses(kind: String) -> Array[Transform3D]:
	var c: Dictionary = DATA[kind]
	var x: float = float(c.width) * 0.5 - float(c.wheel_inset)
	var radius: float = c.wheel_radius
	var poses: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		for z in [float(c.front_axle), float(c.rear_axle)]:
			poses.append(Transform3D(Basis.IDENTITY, Vector3(side * x, radius, z)))
	return poses

static func traffic_kind(index: int) -> String:
	if benchmark_legacy_catalog:
		return str(LEGACY_KINDS[posmod(index,LEGACY_KINDS.size())])
	return str(TRAFFIC_ROTATION[posmod(index, TRAFFIC_ROTATION.size())])

static func parked_kind(index: int) -> String:
	if benchmark_legacy_catalog:
		return str(LEGACY_KINDS[posmod(index,LEGACY_KINDS.size())])
	return str(PARKED_ROTATION[posmod(index, PARKED_ROTATION.size())])

## Unique kinds in first-appearance order, for building one batch pair per kind.
static func rotation_kinds(rotation: Array) -> Array[String]:
	var result: Array[String] = []
	for kind in rotation:
		if not result.has(str(kind)):
			result.append(str(kind))
	return result

# --- Shared profile evaluation (used by the mesh kit and the collision hulls) ---

static func _piecewise(points: Array, z: float) -> float:
	var first: Array = points[0]
	if z <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var a: Array = points[i - 1]
		var b: Array = points[i]
		if z <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var t := 0.0 if span <= 0.0001 else (z - float(a[0])) / span
			return lerpf(float(a[1]), float(b[1]), t)
	var last: Array = points[points.size() - 1]
	return float(last[1])

static func deck(kind: String, z: float) -> float:
	return _piecewise(DATA[kind].deck, z)

## 0 in the body middle, rising to 1 at the lofted front/rear end caps.
static func end_factor(kind: String, z: float) -> Vector2:
	var front := clampf(1.0 - (body_front(kind) - z) / 0.32, 0.0, 1.0)
	var rear := clampf(1.0 - (z - body_rear(kind)) / 0.32, 0.0, 1.0)
	return Vector2(front, rear)

static func half_width(kind: String, z: float) -> float:
	var c: Dictionary = DATA[kind]
	var e := end_factor(kind, z)
	var taper: float = float(c.taper[0]) * e.x * e.x + float(c.taper[1]) * e.y * e.y
	return float(c.width) * 0.5 * (1.0 - taper)

## Visible top of the lower body after the end roll-off.
static func upper(kind: String, z: float) -> float:
	var c: Dictionary = DATA[kind]
	var e := end_factor(kind, z)
	return deck(kind, z) - float(c.droop[0]) * e.x * e.x - float(c.droop[1]) * e.y * e.y

## Underside line: rocker sill, bumper lift at the ends and round wheel arches.
static func bottom(kind: String, z: float) -> float:
	var c: Dictionary = DATA[kind]
	var e := end_factor(kind, z)
	var sill: float = float(c.sill) + float(c.lift[0]) * e.x + float(c.lift[1]) * e.y
	var radius: float = c.wheel_radius
	var arch := radius + float(c.arch_gap)
	var result := sill
	for axle in [float(c.front_axle), float(c.rear_axle)]:
		var offset: float = absf(z - axle)
		if offset < arch:
			var crown := radius + sqrt(maxf(0.0, arch * arch - offset * offset))
			if axle == float(c.rear_axle) and float(c.rear_skirt) > 0.0:
				crown = minf(crown, float(c.rear_skirt))
			result = maxf(result, crown)
	return result

## Arch stations sampled every 30 degrees so the opening reads round.
static func arch_stations(kind: String) -> Array[float]:
	var c: Dictionary = DATA[kind]
	var arch: float = float(c.wheel_radius) + float(c.arch_gap)
	var result: Array[float] = []
	for axle in [float(c.front_axle), float(c.rear_axle)]:
		for step in 7:
			result.append(axle + arch * cos(PI - float(step) * PI / 6.0))
	return result

## Greenhouse cross-section at z: base/top heights and half widths. Linear
## between stations, which is exactly how the lofted shell is built.
static func greenhouse_at(kind: String, z: float) -> Dictionary:
	var stations: Array = DATA[kind].greenhouse
	var count := stations.size()
	var first: Array = stations[0]
	var last: Array = stations[count - 1]
	z = clampf(z, float(first[0]), float(last[0]))
	for i in range(1, count):
		var b: Array = stations[i]
		if z <= float(b[0]) + 0.00001:
			var a: Dictionary = greenhouse_station(kind, i - 1)
			var d: Dictionary = greenhouse_station(kind, i)
			var span: float = float(d.z) - float(a.z)
			var t := 0.0 if span <= 0.0001 else (z - float(a.z)) / span
			return {"z": z, "base": lerpf(a.base, d.base, t), "top": lerpf(a.top, d.top, t),
				"base_half": lerpf(a.base_half, d.base_half, t), "top_half": lerpf(a.top_half, d.top_half, t)}
	return greenhouse_station(kind, count - 1)

static func greenhouse_station(kind: String, index: int) -> Dictionary:
	var c: Dictionary = DATA[kind]
	var stations: Array = c.greenhouse
	var station: Array = stations[index]
	var z: float = station[0]
	var base := upper(kind, z)
	var half := float(c.width) * 0.5
	# Never overhang the rounded deck edge near the tapered body ends.
	var base_half := minf(float(c.base_width) * half, float(c.deck_round) * half_width(kind, z) - 0.004)
	var roof_half := base_half * float(c.roof_width) / float(c.base_width)
	var is_base := index == 0 or index == stations.size() - 1
	var top: float = base + 0.03 if is_base else float(station[1])
	return {"z": z, "base": base, "top": top, "base_half": base_half, "top_half": base_half if is_base else roof_half}

# --- Collision: same schema as city_car_collision.gd parts() -----------------

## [LowerBody, Cabin] convex parts: {name, shape, planes, radius}. LowerBody
## follows the hood/deck profile (no full-height box over the hood); Cabin is
## the exact greenhouse station hull. Pickup beds are solid to rail height.
static func collision_parts(kind: String) -> Array[Dictionary]:
	if _collision_cache.has(kind):
		return _collision_cache[kind]
	var c: Dictionary = DATA[kind]
	var half := float(c.width) * 0.5
	var front := float(c.length) * 0.5 + 0.03
	var rear := -float(c.length) * 0.5 - 0.03
	var lower := PackedVector3Array()
	var mid_y := minf(0.60, float(c.sill) + 0.20)
	# Leave the visible tire face 5mm proud, as the legacy fleet does: the
	# shot cylinder must win over the shared low body hull at an exposed tire.
	var wheel_band := half - float(c.wheel_inset) + float(c.tire_half_width) - 0.005
	for y in [0.08, mid_y]:
		for z in [rear, front]:
			for side in [-1.0, 1.0]:
				lower.append(Vector3(side * wheel_band, y, z))
	var top_z: Array[float] = [rear, front, body_front(kind) - 0.06, body_front(kind) - 0.16,
		body_rear(kind) + 0.06, body_rear(kind) + 0.16]
	for point in c.deck:
		var clamped := clampf(float(point[0]), rear, front)
		var known := false
		for existing in top_z:
			known = known or absf(existing - clamped) < 0.01
		if not known:
			top_z.append(clamped)
	for z in top_z:
		var y := upper(kind, clampf(z, body_rear(kind), body_front(kind)))
		if z < body_rear(kind):
			y = deck(kind, z) # Tailgate spare: the declared deck point covers it.
		for side in [-1.0, 1.0]:
			lower.append(Vector3(side * (half - 0.045), y, z))
	var cabin := PackedVector3Array()
	for index in c.greenhouse.size():
		var station := greenhouse_station(kind, index)
		for side in [-1.0, 1.0]:
			cabin.append(Vector3(side * float(station.base_half), float(station.base) - 0.015, float(station.z)))
			cabin.append(Vector3(side * float(station.top_half), float(station.top) - 0.035, float(station.z)))
			cabin.append(Vector3(side * float(station.top_half) * 0.95, float(station.top), float(station.z)))
	var result: Array[Dictionary] = [_part("LowerBody", lower), _part("Cabin", cabin)]
	_collision_cache[kind] = result
	return result

static func _part(label_name: String, points: PackedVector3Array) -> Dictionary:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var radius := 0.0
	for point in points:
		radius = maxf(radius, point.length())
	# Supporting planes for the swept player-capsule fallback and shot hulls,
	# computed exactly as city_car_collision.gd does for legacy prototypes.
	var planes: Array[Plane] = []
	for a in points.size():
		for b in range(a + 1, points.size()):
			for d in range(b + 1, points.size()):
				var normal := (points[b] - points[a]).cross(points[d] - points[a])
				if normal.length_squared() < 0.0000001:
					continue
				normal = normal.normalized()
				var plane := Plane(normal, normal.dot(points[a]))
				var positive := false
				var negative := false
				for point in points:
					var distance := plane.distance_to(point)
					positive = positive or distance > 0.0001
					negative = negative or distance < -0.0001
					if positive and negative:
						break
				if positive and negative:
					continue
				if positive:
					plane = Plane(-plane.normal, -plane.d)
				var duplicate := false
				for existing in planes:
					if existing.normal.dot(plane.normal) > 0.9999 and absf(existing.d - plane.d) < 0.001:
						duplicate = true
						break
				if not duplicate:
					planes.append(plane)
	return {"name": label_name, "shape": shape, "planes": planes, "radius": radius}
