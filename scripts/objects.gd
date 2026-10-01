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
	rounded_edge(root)
	rounded_face(root,0.013,art_material(front.get_texture(),int(data.effect)))
	rounded_face(root,-0.013,art_material(back.get_texture(),int(data.effect)),true)
	return root

static var pack_mesh: ArrayMesh

static func pack(parent: Node, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	if pack_mesh == null:
		var source = load("res://assets/pack_model/scene.gltf").instantiate()
		var original = source.find_children("*", "MeshInstance3D", true, false)[0].mesh
		pack_mesh = ArrayMesh.new()
		for surface in original.get_surface_count():
			var arrays = original.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var normals = arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				var v = vertices[i]
				vertices[i] = Vector3(v.z+1.2830946,-v.x,v.y-2.1375136)*0.0811054
				var n = normals[i]
				normals[i] = Vector3(n.z,-n.x,n.y)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			var indices = arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var old = indices[i+1]
				indices[i+1] = indices[i+2]
				indices[i+2] = old
			arrays[Mesh.ARRAY_INDEX] = indices
			var smooth = SurfaceTool.new()
			smooth.begin(Mesh.PRIMITIVE_TRIANGLES)
			var uv = arrays[Mesh.ARRAY_TEX_UV]
			for triangle in range(0,indices.size(),3):
				var a=indices[triangle]
				var b=indices[triangle+1]
				var c=indices[triangle+2]
				_subdivide_pack(smooth,[vertices[a],vertices[b],vertices[c]],[normals[a],normals[b],normals[c]],[uv[a],uv[b],uv[c]],2)
			pack_mesh=smooth.commit(pack_mesh)
		source.free()
	var cover = art_viewport(root,Store.pack_layers(data)).get_texture()
	var back = art_viewport(root,Store.pack_layers(data,true)).get_texture()
	for is_strip in [false,true]:
		var surface = MeshInstance3D.new()
		surface.name = "TopSeal" if is_strip else "Wrapper"
		surface.mesh = pack_mesh
		var mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/pack.gdshader")
		mat.set_shader_parameter("cover",cover)
		mat.set_shader_parameter("back_cover",back)
		mat.set_shader_parameter("foil_reference",load("res://assets/pack_model/textures/Deck_MAT01_baseColor.png"))
		mat.set_shader_parameter("strip",is_strip)
		surface.material_override = mat
		root.add_child(surface)
	return root

static func set_tear(root: Node3D, progress: float) -> void:
	for name in ["Wrapper","TopSeal"]:
		var part = root.get_node_or_null(name)
		if part: part.material_override.set_shader_parameter("progress",clampf(progress,0.0,1.0))

static func rounded_outline() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var radius = 0.095
	var corners = [Vector2(0.75-radius,1.05-radius),Vector2(-0.75+radius,1.05-radius),Vector2(-0.75+radius,-1.05+radius),Vector2(0.75-radius,-1.05+radius)]
	for corner in 4:
		for step in 9:
			var a = deg_to_rad(corner*90.0+step*90.0/8.0)
			points.append(corners[corner]+Vector2(cos(a),sin(a))*radius)
	return points

static func rounded_face(parent: Node3D, z: float, mat: Material, back = false) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = rounded_outline()
	for i in points.size():
		for p in [Vector2.ZERO,points[(i+1)%points.size()],points[i]]:
			st.set_normal(Vector3(0,0,1))
			st.set_uv(Vector2(p.x/1.5+0.5,0.5-p.y/2.1))
			st.add_vertex(Vector3(p.x,p.y,0))
	var surface = MeshInstance3D.new()
	surface.mesh=st.commit()
	surface.material_override=mat
	surface.position.z=z
	if back: surface.rotation.y=PI
	parent.add_child(surface)

static func rounded_edge(parent: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = rounded_outline()
	for i in points.size():
		var a = points[i]
		var b = points[(i+1)%points.size()]
		var normal = Vector3(b.y-a.y,a.x-b.x,0).normalized()
		for v in [Vector3(a.x,a.y,-0.012),Vector3(b.x,b.y,0.012),Vector3(a.x,a.y,0.012),Vector3(a.x,a.y,-0.012),Vector3(b.x,b.y,-0.012),Vector3(b.x,b.y,0.012)]:
			st.set_normal(normal)
			st.add_vertex(v)
	var surface=MeshInstance3D.new()
	surface.mesh=st.commit()
	surface.material_override=material(Color("bab6a5"),0.0,0.9)
	parent.add_child(surface)

static func _subdivide_pack(st: SurfaceTool, positions: Array, normals: Array, uvs: Array, depth: int) -> void:
	if depth > 0:
		var p01=(positions[0]+positions[1])/2
		var p12=(positions[1]+positions[2])/2
		var p20=(positions[2]+positions[0])/2
		var n01=(normals[0]+normals[1]).normalized()
		var n12=(normals[1]+normals[2]).normalized()
		var n20=(normals[2]+normals[0]).normalized()
		var u01=(uvs[0]+uvs[1])/2
		var u12=(uvs[1]+uvs[2])/2
		var u20=(uvs[2]+uvs[0])/2
		_subdivide_pack(st,[positions[0],p01,p20],[normals[0],n01,n20],[uvs[0],u01,u20],depth-1)
		_subdivide_pack(st,[p01,positions[1],p12],[n01,normals[1],n12],[u01,uvs[1],u12],depth-1)
		_subdivide_pack(st,[p20,p12,positions[2]],[n20,n12,normals[2]],[u20,u12,uvs[2]],depth-1)
		_subdivide_pack(st,[p01,p12,p20],[n01,n12,n20],[u01,u12,u20],depth-1)
		return
	for i in 3:
		var v: Vector3=positions[i]
		var n: Vector3=normals[i]
		if absf(v.y)<0.715:
			var u=clampf(v.x/0.932+0.5,0.0,1.0)
			var wave=cos(v.y/0.715*PI/2.0)
			var side=1.0 if uvs[i].x<0.5 else -1.0
			var bulge=side*0.035*sin(u*PI)*wave*wave
			var dx=side*0.035*PI/0.932*cos(u*PI)*wave*wave
			var dy=-side*0.035*sin(u*PI)*sin(v.y/0.715*PI)*PI/(2.0*0.715)
			v.z+=bulge
			n=Vector3(n.x-dx*n.z,n.y-dy*n.z,n.z).normalized()
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(v)
