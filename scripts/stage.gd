class_name CardStage
extends SubViewportContainer

signal pack_selected(series_id: String)
signal shelf_swiped(direction: int)
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var display: Node3D
var item: Node3D
var mode = "shelf"
var pressed_at = Vector2.ZERO
var dragging = false
var moved = false
var opening = false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.size = Vector2i(480,900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c151c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("afccd6")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env_node.environment = env
	world.add_child(env_node)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38,-28,0)
	key.light_color = Color("fff0d3")
	key.light_energy = 0.8
	key.shadow_enabled = true
	world.add_child(key)
	var fill = OmniLight3D.new()
	fill.position = Vector3(-3,5,4)
	fill.light_color = Color("98d9ee")
	fill.light_energy = 0.45
	fill.omni_range = 12
	world.add_child(fill)
	camera = Camera3D.new()
	camera.fov = 43
	world.add_child(camera)
	camera.current = true
	display = Node3D.new()
	world.add_child(display)

func clear() -> void:
	for child in display.get_children():
		display.remove_child(child)
		child.queue_free()
	item = null
	opening = false

func shelf(page = 0) -> void:
	clear()
	mode = "shelf"
	camera.fov = 48
	camera.position = Vector3(0,3.8,12.4)
	camera.look_at(Vector3(0,3.65,0))
	var wood = CardObjects.material(Color("322e2b"),0.05,0.7)
	var edge = CardObjects.material(Color("625348"),0.2,0.5)
	var metal = CardObjects.material(Color("161e24"),0.65,0.37)
	var wall = CardObjects.material(Color("15202a"),0.1,0.9)
	CardObjects.box(display,Vector3(20,18,0.1),Vector3(0,4,-1.1),wall)
	CardObjects.box(display,Vector3(20,0.1,20),Vector3(0,-0.35,0),wood)
	CardObjects.box(display,Vector3(5.5,7.5,0.16),Vector3(0,3.45,-0.58),wood)
	for x in [-2.8,2.8]:
		CardObjects.box(display,Vector3(0.16,7.7,1.3),Vector3(x,3.45,0),metal)
	for i in 4:
		var y = 0.15+i*2.25
		CardObjects.box(display,Vector3(5.6,0.13,1.7),Vector3(0,y,0.2),edge)
		CardObjects.box(display,Vector3(5.6,0.17,0.07),Vector3(0,y-0.04,1.05),metal)
		if i > 0:
			var light_mat = CardObjects.material(Color("d5be96"))
			light_mat.emission_enabled = true
			light_mat.emission = Color("e7c794")
			light_mat.emission_energy_multiplier = 1.3
			CardObjects.box(display,Vector3(5.1,0.027,0.06),Vector3(0,y-0.09,0.75),light_mat)
	var series_list = Store.visible_series()
	for slot in 9:
		var index = page*9+slot
		if index >= series_list.size(): continue
		var series = series_list[index]
		var row = floori(slot/3.0)
		var column = slot%3
		var y = 4.65-row*2.25
		var pack = CardObjects.pack(display,series)
		pack.position = Vector3((column-1)*1.56,y+0.95,0.32)
		pack.rotation_degrees = Vector3(-7,(column-1)*-5,0)
		var body = StaticBody3D.new()
		body.set_meta("series_id",series.id)
		pack.add_child(body)
		var shape = CollisionShape3D.new()
		var volume = BoxShape3D.new()
		volume.size = Vector3(1.1,1.85,0.24)
		shape.shape = volume
		body.add_child(shape)
		var label = Label3D.new()
		label.text = "%s · %d" % [series.name.left(7),series.price]
		label.font_size = 30
		label.pixel_size = 0.004
		label.position = Vector3((column-1)*1.56,y-0.03,1.101)
		label.modulate = Color("e1d5bd")
		label.outline_size = 0
		display.add_child(label)

func show_pack(series: Dictionary) -> void:
	clear()
	mode = "pack"
	camera.fov = 43
	camera.position = Vector3(0,0,3.8)
	camera.look_at(Vector3.ZERO)
	item = CardObjects.pack(display,series)
	item.rotation_degrees = Vector3(-4,-12,0)

func show_card(card: Dictionary, back: Array = []) -> void:
	clear()
	mode = "card"
	camera.fov = 43
	camera.position = Vector3(0,0,4.5)
	camera.look_at(Vector3.ZERO)
	var aura = ShaderMaterial.new()
	aura.shader=preload("res://shaders/aura.gdshader")
	aura.set_shader_parameter("aura_color",Store.grade_color(card.grade))
	CardObjects.face(display,Vector2(3.7,4.1),-0.18,aura)
	item = CardObjects.card(display,card,back)
	item.rotation_degrees = Vector3(-4,-12,0)

func set_tear_progress(value: float) -> void:
	if item: CardObjects.set_tear(item,value)

func tear() -> void:
	if item == null: return
	opening = true
	set_tear_progress(1.0)
	var tween = create_tween()
	tween.tween_property(item,"position:y",-3.0,0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(func(): opening=false)

func _gui_input(event: InputEvent) -> void:
	if opening:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressed_at = event.position
			dragging = true
			moved = false
		else:
			var swipe = event.position-pressed_at
			if dragging and moved and mode == "shelf" and absf(swipe.x)>55 and absf(swipe.x)>absf(swipe.y)*1.2:
				shelf_swiped.emit(1 if swipe.x < 0 else -1)
			if dragging and not moved and mode == "shelf":
				var from = camera.project_ray_origin(event.position)
				var ray = PhysicsRayQueryParameters3D.create(from,from+camera.project_ray_normal(event.position)*50)
				var hit = world.get_world_3d().direct_space_state.intersect_ray(ray)
				if not hit.is_empty():
					pack_selected.emit(hit.collider.get_meta("series_id",""))
			dragging = false
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(pressed_at) > 8:
			moved = true
		if item:
			item.rotation.y += event.relative.x*0.012
			item.rotation.x += event.relative.y*0.012
		accept_event()
