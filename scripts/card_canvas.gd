class_name CardCanvas
extends Control

signal selected(index: int)
signal edited
var layers: Array = []
var active = -1
var editable = false
var dragging = false
var resizing = false
var start_mouse = Vector2.ZERO
var start_rect = Rect2()
var logical_size = Vector2(600, 840)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func scale_factor() -> float:
	return minf(size.x / logical_size.x, size.y / logical_size.y)

func set_layers(value: Array) -> void:
	layers = value
	queue_redraw()

func _draw() -> void:
	var factor = scale_factor()
	if factor <= 0:
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	draw_rect(Rect2(Vector2.ZERO, logical_size), Color("111b24"))
	var font = ThemeDB.fallback_font
	for l in layers:
		if not l.get("visible", true):
			continue
		var wh = Vector2(l.w, l.h)
		var center = Vector2(l.x, l.y) + wh / 2
		draw_set_transform(center * factor, deg_to_rad(l.get("rotation", 0)), Vector2.ONE * factor)
		var rect = Rect2(-wh/2, wh)
		var col = Color(l.get("color", "#ffffff"))
		match l.kind:
			"shape":
				draw_rect(rect, col)
			"image":
				var texture = Store.texture(l.value)
				if texture:
					var ratio = minf(wh.x/texture.get_width(), wh.y/texture.get_height())
					if l.get("fit", "contain") == "cover":
						var source = texture.get_size()
						var crop_ratio = maxf(wh.x/source.x, wh.y/source.y)
						var crop_size = wh/crop_ratio
						draw_texture_rect_region(texture, rect, Rect2((source-crop_size)/2,crop_size), col)
					else:
						var target = texture.get_size()*ratio
						draw_texture_rect(texture, Rect2(-target/2, target), false, col)
				else:
					draw_rect(rect, Color("273743"))
					draw_rect(rect.grow(-4), Color("5b7a85"), false, 2)
					draw_line(rect.position, rect.end, Color("5b7a85"), 2)
					draw_line(Vector2(rect.end.x,rect.position.y), Vector2(rect.position.x,rect.end.y), Color("5b7a85"), 2)
			"text":
				var font_size = int(l.get("font_size", 30))
				var paragraph = TextParagraph.new()
				paragraph.width = wh.x
				paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
				paragraph.add_string(str(l.value), font, font_size)
				paragraph.max_lines_visible = maxi(1,int(wh.y/(font_size*1.3)))
				paragraph.draw(get_canvas_item(), rect.position, col)
		if editable and layers.find(l) == active:
			draw_rect(rect, Color("65e5c2"), false, 3)
			draw_rect(Rect2(rect.end-Vector2(10,10),Vector2(20,20)), Color("65e5c2"))
	draw_set_transform(Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point = event.position/scale_factor()
			if active >= 0 and active < layers.size():
				var l = layers[active]
				var center = Vector2(l.x+l.w/2,l.y+l.h/2)
				var local = (point-center).rotated(-deg_to_rad(l.get("rotation",0)))
				if local.distance_to(Vector2(l.w,l.h)/2) < 25 and not l.get("locked",false):
					resizing = true
			if not resizing:
				active = -1
				for i in range(layers.size()-1,-1,-1):
					var l = layers[i]
					if l.get("locked",false) or not l.get("visible",true):
						continue
					var center = Vector2(l.x+l.w/2,l.y+l.h/2)
					var local = (point-center).rotated(-deg_to_rad(l.get("rotation",0)))
					if Rect2(-Vector2(l.w,l.h)/2,Vector2(l.w,l.h)).has_point(local):
						active = i
						break
			if active >= 0:
				var l = layers[active]
				start_rect = Rect2(l.x,l.y,l.w,l.h)
				start_mouse = point
				dragging = not resizing
			selected.emit(active)
			queue_redraw()
		else:
			if dragging or resizing:
				edited.emit()
			dragging = false
			resizing = false
		accept_event()
	elif event is InputEventMouseMotion and active >= 0 and (dragging or resizing):
		var delta = event.position/scale_factor()-start_mouse
		var l = layers[active]
		if resizing:
			# Resize around the original center, also for rotated controls.
			var local_delta = delta.rotated(-deg_to_rad(l.get("rotation",0)))
			l.w = maxf(12,start_rect.size.x+local_delta.x*2)
			l.h = maxf(12,start_rect.size.y+local_delta.y*2)
			l.x = start_rect.get_center().x-l.w/2
			l.y = start_rect.get_center().y-l.h/2
		else:
			l.x = start_rect.position.x+delta.x
			l.y = start_rect.position.y+delta.y
		queue_redraw()
		accept_event()

