extends RefCounted
## Pen Lucy district courthouse, exterior only. Red-brick wings flank a taller central
## block whose four-column stone portico carries the COURTHOUSE frieze and a pediment;
## a modest copper-domed cupola rides the slate ridge. Local origin is the footprint
## centre at grade (y 0) with the entrance facing +Z, and the stairs, ramp and rear
## stoop all stay inside FOOTPRINT. Visual geometry is batched by finish through the
## shared civic mesh kit (nine surfaces). Collision covers only the two main masses,
## the columns and the walkable approach: one slab per terrace, stair flight, ramp and
## stoop, so feet glide over the steps instead of catching on each riser.
const Kit := preload("res://scripts/city/city_civic_mesh_kit.gd")
const FOOTPRINT := Vector2(32.0, 26.0)

const BRICK := "brick"
const STONE := "stone"
const GRANITE := "granite"
const TRIM := "trim"
const GLASS := "glass"
const SLATE := "slate"
const COPPER := "copper"
const METAL := "metal"
const PLANTING := "planting"

# Outward wall normals; x-facing walls use PX * side.
const PX := Vector3(1, 0, 0)
const PZ := Vector3(0, 0, 1)
const NZ := Vector3(0, 0, -1)

# Plan: wings 6.4..15.2 either side of the central block, which projects 1.6 m in
# front of them and 2.4 m behind; the portico stands on the terrace in front of it.
const WING_X := 15.2
const CORE_X := 6.4
const WING_FRONT := 2.4
const WING_BACK := -8.6
const CORE_FRONT := 4.0
const CORE_BACK := -11.0
const COLUMN_Z := 7.0
const COLUMNS := [-6.0, -2.0, 2.0, 6.0]
const RAMP_TOP := 7.4
const RAMP_FOOT := 14.6

# Levels: four 0.15 m risers up to the floor; granite water table under a stone cap.
const FLOOR := 0.6
const BASE_TOP := 1.25
const CAP_TOP := 1.4
const G_SILL := 1.5
const G_HEAD := 4.0
const BELT_LOW := 4.45
const BELT_HIGH := 4.75
const U_SILL := 5.2
const U_HEAD := 7.4
const WING_FRIEZE := 7.85
const ENTABLATURE := 8.2
const WING_ROOF := 8.6
const CORNICE_TOP := 9.85
const EAVE_HALF := 6.92
const ROOF_SLOPE := 0.30573 # tan(17 degrees): a low classical pitch
const RIDGE := CORNICE_TOP + EAVE_HALF * ROOF_SLOPE
const REVEAL := 0.22
const WINDOW_W := 1.25

# Corner order for _hexa: 0-3 one ring, 4-7 the matching ring.
const HEXA_FACES := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]

static func footprint() -> Vector2:
	return FOOTPRINT

static func build() -> Node3D:
	var kit: Kit = Kit.new("PenLucyCourthouse")
	kit.material(BRICK, Color("8c4a3a"), 1, 0.9)
	kit.material(STONE, Color("d4ccbb"), 2, 0.86)
	kit.material(GRANITE, Color("8f8b83"), 2, 0.9)
	kit.material(TRIM, Color("eeeadf"), 6, 0.82)
	kit.material(GLASS, Color("1c232c"), 0, 0.6)
	kit.material(SLATE, Color("4a4e55"), 0, 0.8)
	kit.material(COPPER, Color("6d9283"), 4, 0.7)
	kit.material(METAL, Color("2c2a27"), 0, 0.55)
	kit.material(PLANTING, Color("4f6b36"), 5, 0.95)
	_masses(kit)
	_facades(kit)
	_portico(kit)
	_roofs(kit)
	_cupola(kit)
	_approach(kit)
	_rear_entry(kit)
	_grounds(kit)
	_colliders(kit)
	# Understated inscription on the portico frieze, read from the street (+Z).
	var inscription: Label3D = kit.label("COURTHOUSE", Vector3(0.0, 9.025, 7.47), 46, 0.0105, Color("3b3226"))
	inscription.name = "CourthouseInscription"
	inscription.shaded = true
	var root: Node3D = kit.finish()
	root.set_meta("footprint", FOOTPRINT)
	root.set_meta("entrance", Vector3(0.0, 0.0, 10.6))
	root.set_meta("door", Vector3(0.0, FLOOR, CORE_FRONT + 0.4))
	root.set_meta("ramp_foot", Vector3(15.3, 0.0, 7.8))
	return root

## Interior masses behind the skins, then the bands that wrap the blocks: water
## table, string course, cornices, parapets with coping and the flat wing roof.
static func _masses(kit: Kit) -> void:
	_box(kit, REVEAL - WING_X, WING_X - REVEAL, -0.6, WING_ROOF, WING_BACK + REVEAL, WING_FRONT - REVEAL, BRICK)
	_box(kit, REVEAL - CORE_X, CORE_X - REVEAL, -0.6, CORNICE_TOP, CORE_BACK + REVEAL, CORE_FRONT - REVEAL, BRICK)
	# The central block's rear course is split around the service door; its front
	# stops behind the portico's stone face, which runs down to the terrace.
	_box(kit, -15.26, 15.26, -0.6, BASE_TOP, WING_BACK - 0.06, WING_FRONT + 0.06, GRANITE)
	_box(kit, -15.3, 15.3, BASE_TOP, CAP_TOP, WING_BACK - 0.1, WING_FRONT + 0.1, STONE)
	_box(kit, -6.46, 6.46, -0.6, BASE_TOP, -10.75, CORE_FRONT - REVEAL, GRANITE)
	_box(kit, -6.5, 6.5, BASE_TOP, CAP_TOP, -10.75, CORE_FRONT - REVEAL, STONE)
	_box(kit, -0.85, 0.85, -0.6, FLOOR, CORE_BACK - 0.06, -10.7, GRANITE)
	for side in [-1.0, 1.0]:
		var s: float = side
		_box(kit, s * 0.85, s * 6.46, -0.6, BASE_TOP, CORE_BACK - 0.06, -10.7, GRANITE)
		_box(kit, s * 0.85, s * 6.5, BASE_TOP, CAP_TOP, CORE_BACK - 0.1, -10.7, STONE)
	_box(kit, -15.28, 15.28, BELT_LOW, BELT_HIGH, WING_BACK - 0.08, WING_FRONT + 0.08, STONE)
	_box(kit, -6.48, 6.48, BELT_LOW, BELT_HIGH, CORE_BACK - 0.08, CORE_FRONT + 0.08, STONE)
	# Wings: frieze band, two-step cornice, brick parapet, stone coping, flat roof.
	_box(kit, -15.24, 15.24, WING_FRIEZE, ENTABLATURE, WING_BACK - 0.04, WING_FRONT + 0.04, STONE)
	_box(kit, -15.4, 15.4, ENTABLATURE, 8.36, WING_BACK - 0.2, WING_FRONT + 0.2, STONE)
	_box(kit, -15.6, 15.6, 8.36, WING_ROOF, WING_BACK - 0.4, WING_FRONT + 0.4, STONE)
	_box(kit, -WING_X, WING_X, WING_ROOF, 9.05, WING_FRONT - 0.3, WING_FRONT, BRICK)
	_box(kit, -WING_X, WING_X, WING_ROOF, 9.05, WING_BACK, WING_BACK + 0.3, BRICK)
	_box(kit, -15.26, 15.26, 9.05, 9.2, WING_FRONT - 0.36, WING_FRONT + 0.06, STONE)
	_box(kit, -15.26, 15.26, 9.05, 9.2, WING_BACK - 0.06, WING_BACK + 0.36, STONE)
	for side in [-1.0, 1.0]:
		var s: float = side
		_box(kit, s * (WING_X - 0.3), s * WING_X, WING_ROOF, 9.05, WING_BACK + 0.3, WING_FRONT - 0.3, BRICK)
		_box(kit, s * (WING_X - 0.36), s * (WING_X + 0.06), 9.05, 9.2, WING_BACK + 0.36, WING_FRONT - 0.36, STONE)
	_box(kit, 0.3 - WING_X, WING_X - 0.3, WING_ROOF, 8.72, WING_BACK + 0.3, WING_FRONT - 0.3, SLATE)
	# Central block: architrave, frieze and three-part cornice run round it and over
	# the portico, whose ceiling is the architrave's soffit.
	_box(kit, -6.5, 6.5, ENTABLATURE, 8.7, CORE_BACK - 0.1, 7.5, STONE)
	_box(kit, -6.45, 6.45, 8.7, 9.35, CORE_BACK - 0.05, 7.45, STONE)
	_box(kit, -6.65, 6.65, 9.35, 9.5, CORE_BACK - 0.25, 7.65, STONE)
	_box(kit, -6.88, 6.88, 9.5, 9.78, CORE_BACK - 0.48, 7.88, STONE)
	_box(kit, -EAVE_HALF, EAVE_HALF, 9.78, CORNICE_TOP, CORE_BACK - 0.52, 7.92, STONE)

## Every wall face: masonry skin around real openings, then sashes, glass and dressings.
static func _facades(kit: Kit) -> void:
	var no_doors: Array[Rect2] = []
	var plain: Array[Vector4] = []
	var front_bays: Array[float] = [8.3, 10.8, 13.3]
	var side_bays: Array[float] = [-6.85, -4.35, -1.85, 0.65]
	var flank_bay: Array[float] = [-9.8]
	for side in [-1.0, 1.0]:
		var s: float = side
		var bays: Array[float] = []
		for bay in front_bays:
			bays.append(s * bay)
		var x0 := minf(s * CORE_X, s * WING_X)
		var x1 := maxf(s * CORE_X, s * WING_X)
		_facade(kit, PZ, WING_FRONT, x0, x1, CAP_TOP, WING_FRIEZE, _grid(bays, WINDOW_W), no_doors, BRICK, false)
		_facade(kit, NZ, WING_BACK, x0, x1, CAP_TOP, WING_FRIEZE, _grid(bays, WINDOW_W), no_doors, BRICK, false)
		_facade(kit, PX * s, s * WING_X, WING_BACK, WING_FRONT, CAP_TOP, WING_FRIEZE, _grid(side_bays, WINDOW_W), no_doors, BRICK, false)
		# Central block flanks: plain beside the portico, one narrow bay on the rear projection.
		_facade(kit, PX * s, s * CORE_X, WING_FRONT, CORE_FRONT, CAP_TOP, ENTABLATURE, plain, no_doors, BRICK, false)
		_facade(kit, PX * s, s * CORE_X, CORE_BACK, WING_BACK, CAP_TOP, ENTABLATURE, _grid(flank_bay, 0.9), no_doors, BRICK, false)
		# Stone quoin strips on the outer corners; antae with plinth and capital frame the portico.
		_box(kit, s * 14.55, s * 15.24, CAP_TOP, WING_FRIEZE, WING_FRONT - 0.65, WING_FRONT + 0.04, STONE)
		_box(kit, s * 14.55, s * 15.24, CAP_TOP, WING_FRIEZE, WING_BACK - 0.04, WING_BACK + 0.65, STONE)
		_box(kit, s * 5.75, s * 6.44, CAP_TOP, ENTABLATURE, CORE_BACK - 0.04, CORE_BACK + 0.65, STONE)
		_box(kit, s * 5.5, s * 6.5, FLOOR, ENTABLATURE, CORE_FRONT - 0.25, CORE_FRONT + 0.2, STONE)
		_box(kit, s * 5.44, s * 6.56, FLOOR, 0.85, CORE_FRONT - 0.3, CORE_FRONT + 0.26, STONE)
		_box(kit, s * 5.44, s * 6.56, 7.95, ENTABLATURE, CORE_FRONT - 0.3, CORE_FRONT + 0.26, STONE)
	# Portico face in dressed stone: main door, a window either side, three above; the
	# centre window gets a cornice hood. The rear repeats the bays around a service door.
	var central: Array[Vector4] = [
		Vector4(-4.0, WINDOW_W, G_SILL, G_HEAD), Vector4(4.0, WINDOW_W, G_SILL, G_HEAD),
		Vector4(-4.0, WINDOW_W, U_SILL, U_HEAD), Vector4(0.0, WINDOW_W, U_SILL, U_HEAD),
		Vector4(4.0, WINDOW_W, U_SILL, U_HEAD)]
	var main_door: Array[Rect2] = [Rect2(-1.0, FLOOR, 2.0, 3.3)]
	_facade(kit, PZ, CORE_FRONT, -CORE_X, CORE_X, FLOOR, ENTABLATURE, central, main_door, STONE, true)
	_wbox(kit, PZ, CORE_FRONT, -1.08, 1.08, U_HEAD + 0.24, U_HEAD + 0.4, -0.02, 0.26, STONE)
	var service_door: Array[Rect2] = [Rect2(-0.85, FLOOR, 1.7, 2.7)]
	_facade(kit, NZ, CORE_BACK, -CORE_X, CORE_X, CAP_TOP, ENTABLATURE, central, service_door, BRICK, false)

## Four stone columns (plinth, torus, tapered shaft, echinus, abacus) and the pediment:
## a recessed tympanum with a glazed roundel under raking cornices.
static func _portico(kit: Kit) -> void:
	for value in COLUMNS:
		var x: float = value
		kit.box(Vector3(x, 0.725, COLUMN_Z), Vector3(1.0, 0.25, 1.0), STONE)
		kit.cylinder(Vector3(x, 0.925, COLUMN_Z), 0.5, 0.15, STONE, 12)
		kit.cylinder(Vector3(x, 4.35, COLUMN_Z), 0.42, 6.7, STONE, 16, 0.36)
		kit.cylinder(Vector3(x, 7.81, COLUMN_Z), 0.37, 0.22, STONE, 12, 0.48)
		kit.box(Vector3(x, 8.06, COLUMN_Z), Vector3(1.0, 0.28, 1.0), STONE)
	_gable(kit, 6.45, CORNICE_TOP, 6.45 * ROOF_SLOPE, 6.9, 7.4, STONE)
	_rakes(kit, 7.425)
	var facing := Vector3(PI * 0.5, 0.0, 0.0)
	kit.cylinder(Vector3(0.0, 10.6, 7.45), 0.62, 0.1, STONE, 16, -1.0, facing)
	kit.cylinder(Vector3(0.0, 10.6, 7.47), 0.46, 0.1, GLASS, 16, -1.0, facing)

## Slate gable over the central block, its brick rear pediment and vent, and the
## silhouette pieces that read over the wing parapets: chimneys and a condenser.
static func _roofs(kit: Kit) -> void:
	_gable(kit, EAVE_HALF, CORNICE_TOP, RIDGE - CORNICE_TOP, -10.8, 7.2, SLATE)
	_gable(kit, 6.45, CORNICE_TOP, 6.45 * ROOF_SLOPE, CORE_BACK - 0.05, -10.55, BRICK)
	_rakes(kit, -11.025)
	var facing := Vector3(PI * 0.5, 0.0, 0.0)
	kit.cylinder(Vector3(0.0, 10.55, -11.08), 0.5, 0.1, STONE, 12, -1.0, facing)
	kit.cylinder(Vector3(0.0, 10.55, -11.11), 0.36, 0.1, METAL, 12, -1.0, facing)
	for side in [-1.0, 1.0]:
		var s: float = side
		_box(kit, s * 13.4, s * 14.4, WING_ROOF, 11.2, -3.9, -2.3, BRICK)
		_box(kit, s * 13.32, s * 14.48, 11.2, 11.35, -3.98, -2.22, STONE)
		for value in [-3.5, -2.7]:
			var z: float = value
			kit.cylinder(Vector3(s * 13.9, 11.55, z), 0.14, 0.4, METAL, 8)
	_box(kit, 10.0, 12.0, 8.72, 9.8, -6.6, -5.2, METAL)
	kit.cylinder(Vector3(11.0, 9.86, -5.9), 0.45, 0.12, METAL, 12)

## Raking cornices of one pediment, standing 0.12 m proud of the slate and hanging
## 0.42 m over the tympanum; z is the centre of their 1.05 m depth.
static func _rakes(kit: Kit, z: float) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		var eave := Vector3(s * 7.0, CORNICE_TOP - 0.08 * ROOF_SLOPE, z)
		_beam(kit, eave, Vector3(0.0, RIDGE, z), 0.525, 0.42, 0.12, STONE)

## Painted square base and louvred belfry under an octagonal copper dome and finial,
## riding the ridge so the building reads above the street-front pediment.
static func _cupola(kit: Kit) -> void:
	# Forward of the block's centre so the dome clears the pediment from ~25 m out.
	var z := -1.5
	_box(kit, -1.35, 1.35, 10.6, 13.3, z - 1.35, z + 1.35, TRIM)
	_box(kit, -1.5, 1.5, 13.3, 13.45, z - 1.5, z + 1.5, TRIM)
	_box(kit, -0.95, 0.95, 13.45, 15.05, z - 0.95, z + 0.95, METAL)
	for value in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = value
		_box(kit, corner.x * 0.95 - 0.18, corner.x * 0.95 + 0.18, 13.45, 15.05, z + corner.y * 0.95 - 0.18, z + corner.y * 0.95 + 0.18, TRIM)
	for value in [13.98, 14.52]:
		var y: float = value
		for side in [-1.0, 1.0]:
			var s: float = side
			_box(kit, -0.77, 0.77, y - 0.04, y + 0.04, z + s * 0.95 - 0.04, z + s * 0.95 + 0.04, TRIM)
			_box(kit, s * 0.95 - 0.04, s * 0.95 + 0.04, y - 0.04, y + 0.04, z - 0.77, z + 0.77, TRIM)
	_box(kit, -1.2, 1.2, 15.05, 15.35, z - 1.2, z + 1.2, TRIM)
	_box(kit, -1.32, 1.32, 15.35, 15.47, z - 1.32, z + 1.32, TRIM)
	# Flats of the octagon face the axes, matching the square base.
	var turn := Vector3(0.0, PI / 8.0, 0.0)
	kit.cylinder(Vector3(0.0, 15.57, z), 1.1, 0.2, COPPER, 8, -1.0, turn)
	kit.cylinder(Vector3(0.0, 15.92, z), 1.1, 0.5, COPPER, 8, 0.85, turn)
	kit.cylinder(Vector3(0.0, 16.395, z), 0.85, 0.45, COPPER, 8, 0.4, turn)
	kit.cylinder(Vector3(0.0, 16.795, z), 0.4, 0.35, COPPER, 8, 0.0, turn)
	kit.cylinder(Vector3(0.0, 17.16, z), 0.12, 0.2, COPPER, 8)
	kit.cylinder(Vector3(0.0, 17.3, z), 0.045, 0.8, COPPER, 6)

## Terrace, marble stairs between lantern pedestals, the 1:12 ramp (east), the planter
## that balances it (west), and the bronze main doors in their stone surround.
static func _approach(kit: Kit) -> void:
	_box(kit, -7.4, 7.4, -0.3, 0.55, WING_FRONT, 8.8, GRANITE)
	_box(kit, -7.4, 7.4, 0.55, FLOOR, WING_FRONT, 8.83, STONE)
	for tread in range(1, 4):
		var z0: float = 8.8 + 0.45 * (tread - 1)
		_box(kit, -5.8, 5.8, -0.3, FLOOR - 0.15 * tread, z0, z0 + 0.45, STONE)
	for side in [-1.0, 1.0]:
		var s: float = side
		_box(kit, s * 5.8, s * 7.4, -0.3, 1.1, 8.8, 10.15, GRANITE)
		_box(kit, s * 5.75, s * 7.45, 1.1, 1.2, 8.75, 10.2, STONE)
		_lantern(kit, Vector3(s * 6.6, 1.2, 9.475))
		_box(kit, s * 7.1, s * 7.4, FLOOR, 1.1, WING_FRONT, 6.8, GRANITE)
		_box(kit, s * 7.05, s * 7.45, 1.1, 1.18, WING_FRONT, 6.85, STONE)
	# Ramp: 0.6 m over 7.2 m, a stone running surface between granite guard walls
	# with coping and a rail on four posts each side.
	var surface: Array[Vector2] = [Vector2(RAMP_TOP, -0.3), Vector2(RAMP_TOP, FLOOR), Vector2(RAMP_FOOT, 0.0), Vector2(RAMP_FOOT, -0.3)]
	_slab_z(kit, surface, 7.05, 8.55, STONE)
	var wall: Array[Vector2] = [Vector2(RAMP_TOP, -0.3), Vector2(RAMP_TOP, FLOOR + 0.3), Vector2(RAMP_FOOT, 0.3), Vector2(RAMP_FOOT, -0.3)]
	for value in [Vector2(6.8, 7.05), Vector2(8.55, 8.8)]:
		var band: Vector2 = value
		var mid := (band.x + band.y) * 0.5
		_slab_z(kit, wall, band.x, band.y, GRANITE)
		_beam(kit, Vector3(RAMP_TOP, FLOOR + 0.3, mid), Vector3(RAMP_FOOT, 0.3, mid), 0.16, 0.0, 0.07, STONE)
		_beam(kit, Vector3(RAMP_TOP, FLOOR + 0.95, mid), Vector3(RAMP_FOOT, 0.95, mid), 0.035, 0.03, 0.03, METAL)
		for post in [7.7, 10.0, 12.3, 14.4]:
			var x: float = post
			var walk := FLOOR - (x - RAMP_TOP) / 12.0
			_box(kit, x - 0.03, x + 0.03, walk + 0.36, walk + 0.95, mid - 0.03, mid + 0.03, METAL)
	_box(kit, -RAMP_FOOT, -RAMP_TOP, -0.3, 1.05, 6.8, 8.8, GRANITE)
	_box(kit, -RAMP_FOOT - 0.05, 0.05 - RAMP_TOP, 1.05, 1.13, 6.75, 8.85, STONE)
	_box(kit, 0.2 - RAMP_FOOT, -0.2 - RAMP_TOP, 1.13, 1.7, 7.0, 8.6, PLANTING)
	# Double doors with raised panels, glazed transom, architrave and cornice hood.
	_wbox(kit, PZ, CORE_FRONT, -1.0, 1.0, FLOOR, 3.05, -REVEAL, -0.17, METAL)
	for side in [-1.0, 1.0]:
		var s: float = side
		_wbox(kit, PZ, CORE_FRONT, s * 0.12, s * 0.86, 0.8, 1.7, -0.17, -0.15, METAL)
		_wbox(kit, PZ, CORE_FRONT, s * 0.12, s * 0.86, 1.95, 2.85, -0.17, -0.15, METAL)
		_wbox(kit, PZ, CORE_FRONT, s * 0.33 - 0.03, s * 0.33 + 0.03, 3.2, 3.9, -0.2, -0.15, TRIM)
		_wbox(kit, PZ, CORE_FRONT, s * 1.0, s * 1.32, FLOOR, 3.9, -0.02, 0.12, STONE)
	_wbox(kit, PZ, CORE_FRONT, -1.0, 1.0, 3.05, 3.2, -REVEAL, -0.05, STONE)
	_pane(kit, PZ, CORE_FRONT, -0.2, -1.0, 1.0, 3.2, 3.9, GLASS)
	_wbox(kit, PZ, CORE_FRONT, -1.32, 1.32, 3.9, 4.22, -0.02, 0.12, STONE)
	_wbox(kit, PZ, CORE_FRONT, -1.6, 1.6, 4.22, 4.4, -0.02, 0.3, STONE)

## Service door on the rear projection with a short marble stoop and iron rails.
static func _rear_entry(kit: Kit) -> void:
	_wbox(kit, NZ, CORE_BACK, -0.85, 0.85, FLOOR, 2.75, -REVEAL, -0.17, METAL)
	_wbox(kit, NZ, CORE_BACK, -0.85, 0.85, 2.75, 2.88, -REVEAL, -0.06, STONE)
	_pane(kit, NZ, CORE_BACK, -0.2, -0.85, 0.85, 2.88, 3.3, GLASS)
	_wbox(kit, NZ, CORE_BACK, -1.12, 1.12, 3.3, 3.56, -0.02, 0.1, STONE)
	_box(kit, -1.5, 1.5, -0.3, FLOOR, -11.9, CORE_BACK - 0.06, STONE)
	for tread in range(1, 4):
		var z1: float = -11.9 - 0.3 * (tread - 1)
		_box(kit, -1.5, 1.5, -0.3, FLOOR - 0.15 * tread, z1 - 0.3, z1, STONE)
	for side in [-1.0, 1.0]:
		var s: float = side
		var x := s * 1.42
		_wbox(kit, NZ, CORE_BACK, s * 0.85, s * 1.12, FLOOR, 3.3, -0.02, 0.1, STONE)
		_box(kit, x - 0.025, x + 0.025, 1.47, 1.53, -11.9, CORE_BACK - 0.1, METAL)
		_beam(kit, Vector3(x, 1.5, -11.9), Vector3(x, 1.05, -12.8), 0.025, 0.03, 0.03, METAL)
		for value in [Vector2(-11.15, FLOOR), Vector2(-11.9, FLOOR), Vector2(-12.75, 0.15)]:
			var post: Vector2 = value
			var top := 1.5 if post.x > -12.0 else 1.08
			_box(kit, x - 0.03, x + 0.03, post.y, top, post.x - 0.03, post.x + 0.03, METAL)

## Paved forecourt to the front boundary, the ramp's landing at grade, lawn panels
## and clipped foundation hedges (decorative and non-blocking, like yard hedges).
static func _grounds(kit: Kit) -> void:
	_box(kit, -16.0, 16.0, -0.3, 0.03, 8.8, 13.0, GRANITE)
	_box(kit, RAMP_FOOT, 16.0, -0.3, 0.03, 6.8, 8.8, GRANITE)
	_box(kit, RAMP_TOP, 15.9, -0.3, 0.04, WING_FRONT + 0.06, 6.8, PLANTING)
	_box(kit, -15.9, -RAMP_TOP, -0.3, 0.04, WING_FRONT + 0.06, 8.8, PLANTING)
	for side in [-1.0, 1.0]:
		var s: float = side
		for value in [8.3, 10.8, 13.3]:
			var x: float = s * value
			_box(kit, x - 0.85, x + 0.85, 0.0, 0.85, 2.56, 3.36, PLANTING)

## Seventeen shapes: the two masses, the walkable approach as continuous slopes
## (the stair plane runs through the tread midpoints, within 7.5 cm of every tread),
## its parapets, pedestals and guards at rail height, the columns and the rear stoop.
static func _colliders(kit: Kit) -> void:
	_solid(kit, -15.3, 15.3, -0.6, 9.2, WING_BACK - 0.1, WING_FRONT + 0.06)
	_solid(kit, -6.5, 6.5, -0.6, CORNICE_TOP, CORE_BACK - 0.1, CORE_FRONT + 0.12)
	_solid(kit, -7.4, 7.4, -0.5, FLOOR, WING_FRONT, 8.575)
	var stair: Array[Vector2] = [Vector2(8.575, -0.3), Vector2(8.575, FLOOR), Vector2(10.375, 0.0), Vector2(10.375, -0.3)]
	_solid_x(kit, stair, -5.8, 5.8)
	for side in [-1.0, 1.0]:
		var s: float = side
		_solid(kit, s * 5.8, s * 7.4, -0.3, 1.2, 8.575, 10.2)
		_solid(kit, s * 7.1, s * 7.4, FLOOR, 1.18, WING_FRONT, 6.8)
	for value in COLUMNS:
		var x: float = value
		_solid(kit, x - 0.48, x + 0.48, FLOOR, ENTABLATURE, COLUMN_Z - 0.48, COLUMN_Z + 0.48)
	var ramp: Array[Vector2] = [Vector2(RAMP_TOP, -0.3), Vector2(RAMP_TOP, FLOOR), Vector2(RAMP_FOOT, 0.0), Vector2(RAMP_FOOT, -0.3)]
	_solid_z(kit, ramp, 6.8, 8.8)
	var guard: Array[Vector2] = [Vector2(RAMP_TOP, -0.3), Vector2(RAMP_TOP, FLOOR + 0.95), Vector2(RAMP_FOOT, 0.95), Vector2(RAMP_FOOT, -0.3)]
	_solid_z(kit, guard, 6.8, 7.05)
	_solid_z(kit, guard, 8.55, 8.8)
	_solid(kit, -RAMP_FOOT - 0.05, 0.05 - RAMP_TOP, -0.3, 1.13, 6.75, 8.85)
	var stoop: Array[Vector2] = [Vector2(CORE_BACK, -0.3), Vector2(CORE_BACK, FLOOR), Vector2(-11.75, FLOOR), Vector2(-12.95, 0.0), Vector2(-12.95, -0.3)]
	_solid_x(kit, stoop, -1.5, 1.5)

static func _grid(centers: Array[float], width: float) -> Array[Vector4]:
	var windows: Array[Vector4] = []
	for h in centers:
		windows.append(Vector4(h, width, G_SILL, G_HEAD))
		windows.append(Vector4(h, width, U_SILL, U_HEAD))
	return windows

## One wall face. Openings are (centre, width, bottom, top) windows plus door rects.
static func _facade(kit: Kit, n: Vector3, plane: float, h0: float, h1: float, y0: float, y1: float, windows: Array[Vector4], doors: Array[Rect2], finish: String, dressed: bool) -> void:
	var holes: Array[Rect2] = []
	for door in doors:
		holes.append(door)
	for opening in windows:
		holes.append(Rect2(opening.x - opening.y * 0.5, opening.z, opening.y, opening.w - opening.z))
	_skin(kit, n, plane, h0, h1, y0, y1, holes, finish)
	for opening in windows:
		_window(kit, n, plane, opening.x, opening.y, opening.z, opening.w, dressed)

## Masonry skin of one face (h0..h1 along it, y0..y1) from the reveal depth out to the
## face, leaving the openings. Bands between opening edges are split around them and
## identical spans merge upward, so a wall is a dozen boxes, not one per course.
static func _skin(kit: Kit, n: Vector3, plane: float, h0: float, h1: float, y0: float, y1: float, holes: Array[Rect2], finish: String) -> void:
	var cuts: Array[float] = [y0, y1]
	for hole in holes:
		var edges: Array[float] = [hole.position.y, hole.end.y]
		for y in edges:
			var known := y <= y0 + 0.001 or y >= y1 - 0.001
			for cut in cuts:
				known = known or absf(cut - y) < 0.001
			if not known:
				cuts.append(y)
	cuts.sort()
	var pending: Dictionary = {}
	for i in range(cuts.size() - 1):
		var lo: float = cuts[i]
		var hi: float = cuts[i + 1]
		var crossing: Array[Rect2] = []
		for hole in holes:
			if hole.position.y <= lo + 0.001 and hole.end.y >= hi - 0.001:
				crossing.append(hole)
		crossing.sort_custom(func(p: Rect2, q: Rect2) -> bool: return p.position.x < q.position.x)
		var spans: Array[Vector2] = []
		var cursor := h0
		for hole in crossing:
			if hole.position.x > cursor + 0.001:
				spans.append(Vector2(cursor, hole.position.x))
			cursor = maxf(cursor, hole.end.x)
		if h1 > cursor + 0.001:
			spans.append(Vector2(cursor, h1))
		var carried: Dictionary = {}
		for span in spans:
			carried[span] = pending.get(span, lo)
		for span in pending:
			if not carried.has(span):
				_wbox(kit, n, plane, span.x, span.y, pending[span], lo, -REVEAL, 0.0, finish)
		pending = carried
	for span in pending:
		_wbox(kit, n, plane, span.x, span.y, pending[span], y1, -REVEAL, 0.0, finish)

## A double-hung sash in its reveal: painted frame, recessed glass, meeting rail and
## centre bar, a stone sill carried into the reveal, then either a flat-arch lintel
## with keystone (brick walls) or a full architrave surround (dressed stone face).
static func _window(kit: Kit, n: Vector3, plane: float, h: float, width: float, y0: float, y1: float, dressed: bool) -> void:
	var a := h - width * 0.5
	var b := h + width * 0.5
	_wbox(kit, n, plane, a, b, y0, y1, -REVEAL, -0.15, TRIM)
	_pane(kit, n, plane, -0.135, a + 0.09, b - 0.09, y0 + 0.09, y1 - 0.09, GLASS)
	var rail := y0 + (y1 - y0) * 0.56
	_wbox(kit, n, plane, a + 0.05, b - 0.05, rail - 0.045, rail + 0.045, -0.15, -0.1, TRIM)
	_wbox(kit, n, plane, h - 0.035, h + 0.035, y0 + 0.05, y1 - 0.05, -0.15, -0.11, TRIM)
	var sill := 0.3 if dressed else 0.1
	_wbox(kit, n, plane, a - sill, b + sill, y0 - 0.12, y0 + 0.02, -0.15, 0.13, STONE)
	if dressed:
		_wbox(kit, n, plane, a - 0.22, a, y0 + 0.02, y1, -0.02, 0.08, STONE)
		_wbox(kit, n, plane, b, b + 0.22, y0 + 0.02, y1, -0.02, 0.08, STONE)
		_wbox(kit, n, plane, a - 0.22, b + 0.22, y1, y1 + 0.24, -0.02, 0.08, STONE)
	else:
		_wbox(kit, n, plane, a - 0.13, b + 0.13, y1, y1 + 0.3, -0.02, 0.04, STONE)
		_wbox(kit, n, plane, h - 0.16, h + 0.16, y1 - 0.05, y1 + 0.38, -0.02, 0.08, STONE)

static func _lantern(kit: Kit, base: Vector3) -> void:
	kit.cylinder(base + Vector3(0.0, 0.08, 0.0), 0.13, 0.16, METAL, 8)
	kit.cylinder(base + Vector3(0.0, 0.75, 0.0), 0.06, 1.3, METAL, 8)
	kit.cylinder(base + Vector3(0.0, 1.425, 0.0), 0.25, 0.05, METAL, 6)
	kit.cylinder(base + Vector3(0.0, 1.7, 0.0), 0.21, 0.5, GLASS, 6)
	kit.cylinder(base + Vector3(0.0, 2.09, 0.0), 0.27, 0.28, METAL, 6, 0.04)

static func _box(kit: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, finish: String) -> void:
	kit.box(Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5, Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)), finish)

static func _solid(kit: Kit, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	kit.solid_box(Vector3(x0 + x1, y0 + y1, z0 + z1) * 0.5, Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0)))

## Box on a wall face. h runs along the wall (world x on z-facing walls, world z on
## x-facing walls); v is measured outward from the face, negative into the reveal.
static func _wbox(kit: Kit, n: Vector3, plane: float, h0: float, h1: float, y0: float, y1: float, v0: float, v1: float, finish: String) -> void:
	if absf(n.z) > 0.5:
		_box(kit, h0, h1, y0, y1, plane + n.z * v0, plane + n.z * v1, finish)
	else:
		_box(kit, plane + n.x * v0, plane + n.x * v1, y0, y1, h0, h1, finish)

## Single quad inside a reveal, facing out of the wall (glass is only seen from outside).
static func _pane(kit: Kit, n: Vector3, plane: float, v: float, h0: float, h1: float, y0: float, y1: float, finish: String) -> void:
	if absf(n.z) > 0.5:
		var z := plane + n.z * v
		var quad: Array[Vector3] = [Vector3(h0, y0, z), Vector3(h0, y1, z), Vector3(h1, y1, z), Vector3(h1, y0, z)]
		_facing(kit, quad, n, finish)
	else:
		var x := plane + n.x * v
		var quad: Array[Vector3] = [Vector3(x, y0, h0), Vector3(x, y1, h0), Vector3(x, y1, h1), Vector3(x, y0, h1)]
		_facing(kit, quad, n, finish)

## Fans a planar convex polygon, winding each triangle so the kit's clockwise-front
## normal points along `outward`; collapsed (zero-area) triangles are skipped.
static func _facing(kit: Kit, points: Array[Vector3], outward: Vector3, finish: String) -> void:
	var a: Vector3 = points[0]
	for i in range(1, points.size() - 1):
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 0.000000001:
			continue
		if normal.dot(outward) >= 0.0:
			kit.triangle(a, b, c, finish)
		else:
			kit.triangle(a, c, b, finish)

## Convex six-faced solid from eight corners; coincident corners collapse faces into
## triangles or drop them. Every face turns away from the solid's centre.
static func _hexa(kit: Kit, corners: Array[Vector3], finish: String) -> void:
	var center := Vector3.ZERO
	for corner in corners:
		center += corner
	center /= 8.0
	for face in HEXA_FACES:
		var loop: Array[Vector3] = []
		var middle := Vector3.ZERO
		for index in face:
			var point: Vector3 = corners[int(index)]
			loop.append(point)
			middle += point
		_facing(kit, loop, middle * 0.25 - center, finish)

## Sloped member from a to b, its width across the plan direction: raking cornices,
## copings and handrails.
static func _beam(kit: Kit, a: Vector3, b: Vector3, half_width: float, below: float, above: float, finish: String) -> void:
	var run := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var side := Vector3(-run.z, 0.0, run.x).normalized() * half_width
	var low := Vector3(0.0, -below, 0.0)
	var high := Vector3(0.0, above, 0.0)
	var corners: Array[Vector3] = [a - side + low, b - side + low, b + side + low, a + side + low,
		a - side + high, b - side + high, b + side + high, a + side + high]
	_hexa(kit, corners, finish)

## Gable prism: eaves at x = +-half on `base`, ridge on x 0 `rise` higher, z0..z1.
static func _gable(kit: Kit, half: float, base: float, rise: float, z0: float, z1: float, finish: String) -> void:
	var top := base + rise
	var corners: Array[Vector3] = [Vector3(-half, base, z0), Vector3(half, base, z0), Vector3(half, base, z1), Vector3(-half, base, z1),
		Vector3(0.0, top, z0), Vector3(0.0, top, z0), Vector3(0.0, top, z1), Vector3(0.0, top, z1)]
	_hexa(kit, corners, finish)

## Prism of a four-point (x, y) outline, listed in order around it, from z0 to z1.
static func _slab_z(kit: Kit, outline: Array[Vector2], z0: float, z1: float, finish: String) -> void:
	var corners: Array[Vector3] = []
	var ends: Array[float] = [z0, z1]
	for z in ends:
		for point in outline:
			corners.append(Vector3(point.x, point.y, z))
	_hexa(kit, corners, finish)

## Convex collision prism of a (z, y) outline between x0 and x1.
static func _solid_x(kit: Kit, outline: Array[Vector2], x0: float, x1: float) -> void:
	var points := PackedVector3Array()
	for point in outline:
		points.append(Vector3(x0, point.y, point.x))
		points.append(Vector3(x1, point.y, point.x))
	kit.solid_convex(points)

## Convex collision prism of an (x, y) outline between z0 and z1.
static func _solid_z(kit: Kit, outline: Array[Vector2], z0: float, z1: float) -> void:
	var points := PackedVector3Array()
	for point in outline:
		points.append(Vector3(point.x, point.y, z0))
		points.append(Vector3(point.x, point.y, z1))
	kit.solid_convex(points)
