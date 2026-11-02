extends "res://tests/city_combat_reactions_smoke_runner.gd"
## Retained combat backend coverage; the playable nonviolent policy stays off.
const WorldAudio = preload("res://scripts/city/city_world_audio.gd")

class BackendCombat:
	extends "res://scripts/city/city_combat.gd"
	# A test-only policy override exercises the retained implementation without
	# adding a production switch, setting or command-line unlock.
	func player_offense_enabled() -> bool:
		return true

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0,-.5,0),Vector3(240,1,240),1)
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	npcs = PeopleFixture.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	arena.residents = PeopleFixture.new()
	arena.add_child(arena.residents)
	var playable_policy := Combat.new()
	check(not playable_policy.player_offense_enabled(), "playable build still rejects player offense")
	playable_policy.free()
	combat = BackendCombat.new()
	arena.add_child(combat)
	combat.setup(arena)
	reset_player()
	var victim := spawn("assault_victim",Vector3(0,.012,5),PI)
	var visible := spawn("visible_witness",Vector3(-4,.012,1.5),PI/2)
	var officer := spawn("officer",Vector3(4,.012,1.5),-PI/2)
	var hidden := spawn("hidden_witness",Vector3(6,.012,6),-PI/2)
	var distant := spawn("far_witness",Vector3(-20,.012,1.35),PI/2)
	var facing_away := spawn("unseeing_witness",Vector3(-4,.012,-3),PI)
	box(Vector3(3,1.5,3),Vector3(.2,3,2),2)
	await frames(2)
	combat.combo = 1
	combat._punch_hit()
	check(combat.assault_events==0,"missed swing emits no assault witness event")
	victim.position = Vector3(0,.012,1.35)
	await frames(2)
	check(combat.request_attack(),"explicit backend fixture policy starts retained melee attack")
	combat.tick(.1)
	combat.tick(.1)
	check(combat.hits_landed==1 and combat.assault_events==1,"production landed punch emits exactly one witness event")
	check(combat._panic.has(visible.get_instance_id()),"visible civilian witness enters existing flee behavior")
	check(combat._active.has(officer.get_instance_id()) and combat._active[officer.get_instance_id()].mode=="aggro",
		"police who see the punch intervene using existing melee response")
	check(not combat.last_assault.observed.has(hidden.actor_id),"real wall blocks witness sight to assault")
	check(not combat.last_assault.observed.has(distant.actor_id),"out-of-range bystander does not witness assault")
	check(not combat.last_assault.observed.has(facing_away.actor_id),"bystander looking away does not gain omniscient sight")
	check(combat.npc_shots==0,"melee witnessing does not invent firearm escalation or wanted heat")
	# Background residents use real cell indexing and existing cheap panic,
	# without promoting witnesses into independent full combat actors.
	crowd = Crowd.new()
	npcs.add_child(crowd)
	npcs.crowd = crowd
	crowd.level = arena
	crowd.npcs = npcs
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = .24
	crowd._shape.height = 1.65
	crowd._meshes.assign([crowd._person_mesh(false),crowd._person_mesh(true)])
	crowd._add_resident(Vector3(-5,.012,-3),.9,"social",false)
	crowd._add_resident(Vector3(80,.012,80),PI,"social",false)
	crowd._build_batches()
	await frames(2)
	combat._damage_target(victim,1.0,"punch")
	check(crowd.residents[0].get("panic",false) and not crowd.residents[0].get("combat_controlled",false),
		"visible background witness panics through production crowd path without promotion")
	check(not crowd.residents[1].get("panic",false),"remote crowd cells remain untouched by melee")
	for i in 36:
		var angle := TAU*float(i)/36.0
		var radius := 8.0 if i%2==0 else 12.0
		spawn("budget_witness_%02d"%i,Vector3(sin(angle)*radius,.012,cos(angle)*radius),angle+PI)
	await frames(2)
	combat._damage_target(victim,1.0,"punch")
	check(int(combat.last_assault.checked)<=Combat.MAX_MELEE_WITNESS_CHECKS and int(combat.last_assault.rays)<=Combat.MAX_MELEE_WITNESS_CHECKS*2,
		"dense assault event has a strict24-witness48-ray ceiling")
	check(combat._active.size()<=Combat.MAX_ACTIVE and combat._panic.size()<=Combat.MAX_PANIC and crowd._panic.size()<=Crowd.PANIC_TOTAL,
		"witness reactions preserve all existing actor and crowd budgets")
	await _audio_pool()
	print("[melee_audio] last_assault ",JSON.stringify(combat.last_assault))
	arena.queue_free()
	await frames(2)
	print("[melee_audio] %d passed; %d failed" % [passes,failures])
	get_tree().quit(0 if failures==0 else 1)

func _audio_pool() -> void:
	var pool: Node3D = combat.world_audio
	check(pool==WorldAudio.ensure(arena) and pool.voices.size()==WorldAudio.MAX_VOICES,"combat and vehicle audio share one fixed12-voice pool")
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050*4)
	stream.data = samples
	var origin := Vector3(3,1.2,4)
	var index: int = pool.play_world(stream,origin,40.0,-9.0,3.0,"fixture")
	check(index>=0,"nearby world event receives a spatial voice")
	if index>=0:
		var voice: AudioStreamPlayer3D = pool.voices[index]
		check(voice.global_position.is_equal_approx(origin) and voice.bus==&"SFX" and voice.max_distance==40.0
			and voice.attenuation_model==AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE,
			"voice uses true source position, distance attenuation and existing SFX bus")
	for i in 40:
		pool.play_world(stream,Vector3(float(i%3),1,3),40.0,-9.0,3.0,"burst")
	check(pool.voices.size()==12 and pool.get_child_count()==12 and int(pool.get_status().reused)>0,
		"saturated pool reuses oldest voices without allocating extra nodes")
	var count: int = pool.played
	check(pool.play_world(stream,Vector3(1000,1,1000),40.0)==-1 and pool.played==count,
		"inaudible distant events do not consume a voice")
	# Spatial play requests become active on the physics/audio update.
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
	pool.sync_pause()
	var paused := true
	for voice in pool.voices:
		paused = paused and bool(voice.stream_paused)
	check(paused and pool.play_world(stream,origin)==-1,"pause freezes active world voices and declines queued world events")
	get_tree().paused = false
	pool.sync_pause()
	check(not pool.voices[0].stream_paused,"world audio resumes without replacing its pool")
	check(pool.honk(Vector3(2,.8,4))>=0 and pool.last_event.tag=="horn","existing horn asset plays through the shared spatial pool")
