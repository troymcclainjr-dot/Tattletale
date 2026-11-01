extends "res://tests/city_tire_handling_smoke_runner.gd"
const Renderer = preload("res://scripts/city/city_vehicle_render_lod.gd")
const Models = preload("res://scripts/city/city_car_models.gd")
const Explorer = preload("res://scripts/city/city_player.gd")
func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = Node3D.new()
	add_child(world)
	box(Vector3(0,-.5,50),Vector3(300,1,300),1)
	level = LevelFixture.new()
	world.add_child(level)
	level.player = Explorer.new()
	level.add_child(level.player)
	level.player.set_physics_process(false)
	level.player.enabled = true
	var street := StreetFixture.new()
	street.level = level
	street.half_width = 150.0
	world.add_child(street)
	await get_tree().physics_frame
	var cars: Array[Node3D] = []
	for i in 3:
		var car := Vehicle.new()
		street.add_child(car)
		var x := float(i)*5.0
		var path: Array[Vector3] = [Vector3(x,0,70),Vector3(x,0,120)]
		check(car.setup(street,path,"lod_%d"%i,8.0,i*13,i==2),"LOD fixture vehicle setup%d"%i)
		cars.append(car)
	var renderer: Node3D = street.get_node("MovingVehicleRenderLOD")
	renderer.set_process(false)
	renderer.enabled = true
	var first: Node3D = cars[0]
	var second: Node3D = cars[1]
	var physical_layer: int = first.collision_layer
	var physical_shape: Shape3D = first.collision_parts[0].shape
	var physical_pose: Transform3D = first.global_transform
	renderer.refresh(Vector3.ZERO)
	check(first._render_lod_active and second._render_lod_active and not first.model.visible
		and renderer.get_status().batched==2 and renderer.get_status().active_batches==1,
		"two distant healthy cars share one merged kind batch")
	var batch: Dictionary = renderer.batches.box_sedan
	check(batch.multi.mesh==Models.prototype("box_sedan").far_parked and batch.members.size()==2,
		"distant mesh reuses cached complete body-and-wheel resource")
	check(batch.colors[first._render_lod_slot]==Renderer.paint_tint(Models.paint_color(0)) and batch.colors[second._render_lod_slot]==Renderer.paint_tint(Models.paint_color(13)),
		"batch retains distinct per-car paint in renderer color space")
	check(first.collision_layer==physical_layer and first.collision_parts[0].shape==physical_shape and first.global_transform==physical_pose,
		"LOD changes no physical layer, hull or world pose")
	check(not cars[2]._render_lod_active and cars[2].model.visible,"imported police car retains individual geometry")
	var uploads: int = renderer.pose_uploads
	renderer.update_vehicle(first)
	check(renderer.pose_uploads==uploads,"stationary far car avoids redundant instance uploads")
	first.global_position.z += 1.0
	renderer.update_vehicle(first)
	check(batch.poses[first._render_lod_slot]==first.global_transform and renderer.pose_uploads==uploads+1,
		"far instance receives current authoritative moving pose")
	first.global_position.z = 50.0
	renderer.refresh(Vector3.ZERO)
	check(first._render_lod_active,"55m/45m hysteresis retains far mode in middle band")
	first.global_position.z = 40.0
	renderer.refresh(Vector3.ZERO)
	check(not first._render_lod_active and first.model.visible and second._render_lod_slot==0
		and batch.members[0]==second and batch.colors[0]==Renderer.paint_tint(Models.paint_color(13)),
		"near model returns and slot compaction preserves remaining car color")
	first.global_position.z = 70.0
	renderer.refresh(Vector3.ZERO)
	first.receive_gunshot({"tire_index":0},Vector3.ZERO)
	check(not first._render_lod_active and first.model.visible and 0 in first.flat_tires
		and first._wheels[0].position.y<first._wheel_positions[0].y,
		"shooting a batched car immediately restores exact damaged wheel geometry")
	var preserved_layer: int = second.collision_layer
	level.player.camera.global_position = second.global_position+Vector3(0,2,3)
	renderer.refresh_vehicle(second)
	check(not second._render_lod_active and second.model.visible and second.collision_layer==preserved_layer,
		"inspector camera proximity selects full model independently of player physics")
	second.global_position.z = 400.0
	renderer.refresh(Vector3.ZERO)
	check(not second.model.visible and not second._render_lod_active,"outer visual cutoff removes batch without changing collider")
	second.global_position.z = 70.0
	renderer.enabled = false
	renderer.refresh(Vector3.ZERO)
	check(second.model.visible and renderer.get_status().batched==0,"counterfactual disables batching and retains individual models")
	renderer.enabled = true
	renderer.refresh(Vector3.ZERO)
	second.queue_free()
	await get_tree().process_frame
	check(renderer.get_status().batched==0 and renderer.vehicles.size()==2,"freed vehicle leaves no ghost instance or stale registration")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures==0 else 1)
