class_name CardObjects
extends RefCounted

static func material(color: Color, metal = 0.0, roughness = 0.5) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = roughness
	return mat

static func box(parent: Node3D, dimensions: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

static func art_viewport(parent: Node, layers: Array) -> SubViewport:
	var vp = SubViewport.new()
	vp.size = Vector2i(600,840)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(vp)
	var canvas = CardCanvas.new()
	canvas.size = Vector2(600,840)
	canvas.layers = layers
	vp.add_child(canvas)
	return vp

static func art_material(texture: Texture2D, effect: int, wrapper = false) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/foil.gdshader")
	mat.set_shader_parameter("artwork", texture)
	mat.set_shader_parameter("effect", effect)
	mat.set_shader_parameter("wrapper", wrapper)
	mat.set_shader_parameter("artwork_aspect", float(texture.get_width())/maxi(1,texture.get_height()))
	return mat

static func face(parent: Node3D, dimensions: Vector2, z: float, mat: Material, back = false) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = QuadMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = mat
	node.position.z = z
	if back:
		node.rotation.y = PI
	parent.add_child(node)
	return node

static func card(parent: Node, data: Dictionary, back_layers: Array = []) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var front = art_viewport(root, data.front)
	var back = art_viewport(root, back_layers if not back_layers.is_empty() else data.back)
	box(root, Vector3(1.5,2.1,0.022), Vector3.ZERO, material(Color("c0b898"),0.45,0.32))
	face(root, Vector2(1.5,2.1),0.013,art_material(front.get_texture(),int(data.effect)))
	face(root, Vector2(1.5,2.1),-0.013,art_material(back.get_texture(),int(data.effect)),true)
	return root

static func pack(parent: Node, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var silver = material(Color("b3c1c8"),0.86,0.27)
	# Slightly inflated wrapper with pinched edges and physically ridged seals.
	var cover = Store.texture(data.get("cover", ""))
	if cover == null:
		cover = load("res://assets/art_0.svg")
	var back = Store.texture(data.get("pack_back", ""))
	if back == null:
		back = load("res://assets/back.svg")
	box(root,Vector3(1.0,1.52,0.09),Vector3.ZERO,silver)
	for side in [false,true]:
		var mesh = SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cols = 12
		var rows = 20
		for y in rows:
			for x in cols:
				for offset in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
					var u = float(x+offset.x)/cols
					var v = float(y+offset.y)/rows
					var bulge = sin(u*PI)*sin(v*PI)*0.055
					var z = (0.05+bulge)*( -1.0 if side else 1.0)
					mesh.set_uv(Vector2(1-u if side else u,v))
					mesh.add_vertex(Vector3(u-0.5,(0.5-v)*1.52,z))
		mesh.generate_normals()
		var surface = MeshInstance3D.new()
		surface.mesh = mesh.commit()
		surface.material_override = art_material(back if side else cover,0,true)
		root.add_child(surface)
	for sign_y in [-1,1]:
		var seam = Node3D.new()
		seam.name = "TopSeal" if sign_y == 1 else "BottomSeal"
		root.add_child(seam)
		seam.position.y = sign_y*0.765
		box(seam,Vector3(1.06,0.12,0.033),Vector3.ZERO,silver)
		var ridges = MultiMeshInstance3D.new()
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var ridge = BoxMesh.new()
		ridge.size = Vector3(0.009,0.117,0.048)
		multimesh.mesh = ridge
		multimesh.instance_count = 44
		for i in 44:
			multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(-0.52+i*0.024,0,0)))
		ridges.multimesh = multimesh
		ridges.material_override = silver
		seam.add_child(ridges)
	return root
