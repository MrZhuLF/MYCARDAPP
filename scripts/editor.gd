class_name CardEditor
extends PanelContainer

signal closed
signal image_requested(callback: Callable)
signal preview_requested(card: Dictionary, back: Array)
signal notify(message: String)
var series_id = ""
var original_id = ""
var draft: Dictionary
var shared_only = false
var series_surface = ""
var side = "front"
var canvas: CardCanvas
var list: ItemList
var properties: VBoxContainer
var templates: OptionButton
var undo_stack: Array = []
var redo_stack: Array = []
var saved_state: Dictionary = {}
var dirty = false
var body: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout = UI.column(self)
	var top = UI.row(layout)
	UI.button(top,"返回",request_close)
	UI.button(top,"预览",func(): preview_requested.emit(draft,back_layers()),true)
	UI.button(top,"保存",save)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	body = UI.column(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not shared_only:
		var name_field = UI.field(body,draft.name,"卡牌名称")
		name_field.text_changed.connect(func(t): draft.name=t; update_text_placeholder("名称",t); mark_edit())
		var info = UI.row(body)
		var grade = UI.select(info,Store.GRADES,maxi(0,Store.GRADES.find(draft.grade)))
		if draft.grade not in Store.GRADES:
			grade.add_item(draft.grade)
			grade.select(grade.item_count-1)
		var effect = UI.select(info,["无特效","金光","镭射","彩色"],int(draft.effect))
		grade.item_selected.connect(func(index):
			draft.grade=grade.get_item_text(index)
			var preset = mini(index,3)
			draft.effect=preset; effect.select(preset)
			mark_edit())
		if Store.vault_unlocked:
			var hidden = CheckButton.new()
			hidden.text="放入保险箱"
			hidden.button_pressed=draft.get("hidden",false)
			body.add_child(hidden)
			hidden.toggled.connect(func(v): draft["hidden"]=v; mark_edit())
		effect.item_selected.connect(func(i): draft.effect=i; mark_edit())
		var stock_row = UI.row(body)
		UI.label(stock_row,"剩余张数")
		UI.number(stock_row,draft.remaining).value_changed.connect(func(v): draft.remaining=int(v); mark_edit())
		var attrs = UI.field(body,draft.get("attributes",""),"属性，例如 ATK 120 / DEF 80")
		attrs.text_changed.connect(func(t): draft.attributes=t; update_text_placeholder("属性",t); mark_edit())
		var shared = CheckButton.new()
		shared.text = "使用系列通用卡背"
		shared.button_pressed = draft.get("shared_back",true)
		body.add_child(shared)
		shared.toggled.connect(func(v): draft.shared_back=v; mark_edit(); refresh_canvas())
		var side_row = UI.row(body)
		UI.button(side_row,"正面",func(): side="front"; refresh_canvas(),true)
		UI.button(side_row,"背面",func(): side="back"; refresh_canvas(),true)
	var center = CenterContainer.new()
	body.add_child(center)
	canvas = CardCanvas.new()
	canvas.editable = true
	canvas.custom_minimum_size = Vector2(280,392)
	canvas.size = Vector2(280,392)
	center.add_child(canvas)
	canvas.selected.connect(func(_index): refresh_properties(); list.select(canvas.active) if canvas.active >= 0 else list.deselect_all())
	canvas.edited.connect(func(): mark_edit(); refresh_properties())
	var add_row = UI.row(body)
	UI.button(add_row,"＋图片",func(): add_layer("image"),true)
	UI.button(add_row,"＋文字",func(): add_layer("text"),true)
	UI.button(add_row,"＋色块",func(): add_layer("shape"),true)
	list = ItemList.new()
	list.custom_minimum_size.y = 142
	list.add_theme_constant_override("v_separation",9)
	body.add_child(list)
	list.item_selected.connect(func(i): canvas.active=i; canvas.queue_redraw(); refresh_properties())
	var tools = UI.row(body)
	UI.button(tools,"↓",func(): reorder(-1),true)
	UI.button(tools,"↑",func(): reorder(1),true)
	UI.button(tools,"复制",duplicate_layer,true)
	UI.button(tools,"删除",delete_layer,true)
	var alignment = UI.row(body)
	UI.button(alignment,"水平居中",func(): center_layer(true),true)
	UI.button(alignment,"垂直居中",func(): center_layer(false),true)
	var history = UI.row(body)
	UI.button(history,"撤销",undo,true)
	UI.button(history,"重做",redo,true)
	properties = UI.column(body)
	var template_row = UI.row(body)
	templates = UI.select(template_row,[])
	UI.button(template_row,"应用",apply_template)
	var template_actions = UI.row(body)
	UI.button(template_actions,"另存模板",save_template,true)
	UI.button(template_actions,"更新模板",update_template,true)
	UI.button(template_actions,"删除模板",delete_template,true)
	refresh_templates()
	refresh_canvas()
	saved_state = draft.duplicate(true)
	undo_stack = [saved_state.duplicate(true)]

func update_text_placeholder(label: String, text: String) -> void:
	for l in draft.front:
		if l.kind == "text" and l.label == label and l.get("placeholder",true):
			l.value = text

func back_layers() -> Array:
	if draft.get("shared_back",false) and not shared_only:
		return Store.series_by_id(series_id).get("back",Store.default_back())
	return draft.back

func is_shared_view() -> bool:
	return side == "back" and draft.get("shared_back",false) and not shared_only

func refresh_canvas() -> void:
	canvas.active = -1
	canvas.editable = not is_shared_view()
	canvas.set_layers(back_layers() if side == "back" else draft.front)
	refresh_list()
	refresh_properties()

func refresh_list() -> void:
	list.clear()
	for l in canvas.layers:
		list.add_item(("◉ " if l.get("visible",true) else "○ ") + l.label + ("  ◆" if l.get("locked",false) else ""))
	if canvas.active >= 0 and canvas.active < canvas.layers.size():
		list.select(canvas.active)

func mark_edit() -> void:
	dirty = true
	undo_stack.append(draft.duplicate(true))
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	redo_stack.clear()
	if canvas:
		canvas.queue_redraw()

func undo() -> void:
	if undo_stack.size() < 2:
		return
	redo_stack.append(undo_stack.pop_back())
	restore_design(undo_stack.back())

func redo() -> void:
	if redo_stack.is_empty():
		return
	var value = redo_stack.pop_back()
	undo_stack.append(value.duplicate(true))
	restore_design(value)

func restore_design(value: Dictionary) -> void:
	# History intentionally concerns the canvas; metadata controls stay in sync.
	draft.front = value.front.duplicate(true)
	draft.back = value.back.duplicate(true)
	dirty = true
	refresh_canvas()

func add_layer(kind: String) -> void:
	if is_shared_view():
		notify.emit("请先关闭通用卡背，或在系列设置中编辑")
		return
	var l = Store.layer(kind,{"image":"图片","text":"文字","shape":"色块"}[kind],[100,150,300,240],"占位文字" if kind == "text" else "")
	canvas.layers.append(l)
	canvas.active = canvas.layers.size()-1
	mark_edit()
	refresh_list()
	refresh_properties()
	if kind == "image":
		import_into(l)

func import_into(l: Dictionary) -> void:
	image_requested.emit(func(path): l.value=path; mark_edit(); refresh_properties())

func import_dropped(path: String) -> void:
	if is_shared_view():
		return
	var imported = Store.import_image(path)
	if imported.is_empty():
		notify.emit(Store.last_error)
		return
	var l = Store.layer("image","图片",[50,80,500,600],imported)
	canvas.layers.append(l)
	canvas.active = canvas.layers.size()-1
	mark_edit()
	refresh_list()
	refresh_properties()

func current() -> Dictionary:
	if canvas.active < 0 or canvas.active >= canvas.layers.size() or is_shared_view():
		return {}
	return canvas.layers[canvas.active]

func center_layer(horizontal: bool) -> void:
	var l = current()
	if l.is_empty() or l.get("locked",false): return
	if horizontal: l.x=(600.0-l.w)/2.0
	else: l.y=(840.0-l.h)/2.0
	mark_edit()
	refresh_properties()

func refresh_properties() -> void:
	UI.clear(properties)
	if is_shared_view():
		UI.label(properties,"系列通用卡背",15,Color("8da2aa"))
		return
	var l = current()
	if l.is_empty():
		return
	var name_input = UI.field(properties,l.label,"图层名称")
	name_input.text_changed.connect(func(t): l.label=t; mark_edit(); refresh_list())
	if l.kind == "text":
		var text = TextEdit.new()
		text.text = l.value
		text.custom_minimum_size.y = 100
		properties.add_child(text)
		text.text_changed.connect(func(): l.value=text.text; mark_edit())
		var text_row = UI.row(properties)
		UI.label(text_row,"字号")
		UI.number(text_row,l.get("font_size",30),8,250).value_changed.connect(func(v): l.font_size=v; mark_edit())
	elif l.kind == "image":
		var image_row = UI.row(properties)
		UI.button(image_row,"替换原图",func(): import_into(l),true)
		var fit = UI.select(image_row,["完整显示","裁切铺满"],1 if l.get("fit") == "cover" else 0)
		fit.item_selected.connect(func(i): l.fit="contain" if i == 0 else "cover"; mark_edit())
		var source = Store.texture(l.value)
		if source:
			UI.label(properties,"%d × %d" % [source.get_width(),source.get_height()],13,Color("8da2aa"))
	for pair in [["X","x","Y","y"],["宽","w","高","h"]]:
		var row = UI.row(properties)
		for i in [0,2]:
			UI.label(row,pair[i],14)
			var key = pair[i+1]
			var minimum = 1 if key in ["w","h"] else -4000
			UI.number(row,l[key],minimum,4000).value_changed.connect(func(v): l[key]=v; mark_edit())
	var rotation_row = UI.row(properties)
	UI.label(rotation_row,"旋转",14)
	UI.number(rotation_row,l.get("rotation",0),-360,360).value_changed.connect(func(v): l.rotation=v; mark_edit())
	var color = ColorPickerButton.new()
	color.color = Color(l.get("color","#ffffff"))
	color.custom_minimum_size = Vector2(65,44)
	rotation_row.add_child(color)
	color.color_changed.connect(func(c): l.color="#"+c.to_html(); mark_edit())
	var flags = UI.row(properties)
	for pair in [["占位","placeholder"],["显示","visible"],["锁定","locked"]]:
		var check = CheckButton.new()
		check.text = pair[0]
		check.button_pressed = l.get(pair[1],false)
		flags.add_child(check)
		var key = pair[1]
		check.toggled.connect(func(v): l[key]=v; mark_edit(); refresh_list())

func reorder(direction: int) -> void:
	if current().is_empty():
		return
	var target = canvas.active+direction
	if target < 0 or target >= canvas.layers.size():
		return
	var l = canvas.layers.pop_at(canvas.active)
	canvas.layers.insert(target,l)
	canvas.active = target
	mark_edit()
	refresh_list()

func duplicate_layer() -> void:
	if current().is_empty():
		return
	var l = current().duplicate(true)
	l.id = Store.uid()
	l.x += 15
	l.y += 15
	canvas.layers.append(l)
	canvas.active = canvas.layers.size()-1
	mark_edit()
	refresh_list()
	refresh_properties()

func delete_layer() -> void:
	if current().is_empty():
		return
	canvas.layers.remove_at(canvas.active)
	canvas.active = -1
	mark_edit()
	refresh_list()
	refresh_properties()

func refresh_templates() -> void:
	templates.clear()
	for i in Store.data.templates.size():
		var t = Store.data.templates[i]
		if not Store.visible_item(t): continue
		templates.add_item(t.name)
		templates.set_item_metadata(templates.item_count-1,i)

func save_template() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "保存模板"
	var input = LineEdit.new()
	input.text = draft.name
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var before = Store.data.duplicate(true)
		Store.data.templates.append({"id":Store.uid(),"name":input.text,"hidden":draft.get("hidden",false) or Store.series_by_id(series_id).get("hidden",false),"front":draft.front.duplicate(true),"back":draft.back.duplicate(true)})
		if Store.commit(before): refresh_templates(); notify.emit("模板已保存")
		else: notify.emit(Store.last_error)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(330,140))

func apply_template() -> void:
	if templates.selected < 0:
		return
	var t = Store.data.templates[templates.get_item_metadata(templates.selected)]
	for face_name in ["front","back"]:
		var replacements = {}
		for l in draft[face_name]:
			if l.get("placeholder",false): replacements[l.label] = l.value
		draft[face_name] = t[face_name].duplicate(true)
		for l in draft[face_name]:
			l.id = Store.uid()
			if l.get("placeholder",false) and replacements.has(l.label): l.value = replacements[l.label]
	mark_edit()
	refresh_canvas()

func delete_template() -> void:
	if templates.selected < 0:
		return
	var id = Store.data.templates[templates.get_item_metadata(templates.selected)].id
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "删除此模板？"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var before = Store.data.duplicate(true)
		Store.data.templates = Store.data.templates.filter(func(t): return t.id != id)
		if not Store.commit(before): notify.emit(Store.last_error)
		refresh_templates(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func update_template() -> void:
	if templates.selected < 0:
		return
	var index = int(templates.get_item_metadata(templates.selected))
	var dialog = ConfirmationDialog.new()
	dialog.title = "更新模板"
	var input = LineEdit.new()
	input.text = Store.data.templates[index].name
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var before = Store.data.duplicate(true)
		Store.data.templates[index].name = input.text
		Store.data.templates[index].front = draft.front.duplicate(true)
		Store.data.templates[index].back = draft.back.duplicate(true)
		Store.data.templates[index]["hidden"]=draft.get("hidden",false) or Store.series_by_id(series_id).get("hidden",false)
		if Store.commit(before): refresh_templates(); notify.emit("模板已更新")
		else: notify.emit(Store.last_error)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(330,140))

func save() -> void:
	if draft.name.strip_edges().is_empty():
		notify.emit("请输入卡牌名称")
		return
	var before = Store.data.duplicate(true)
	var s = Store.series_by_id(series_id)
	if s.is_empty():
		return
	if not series_surface.is_empty():
		s[series_surface] = draft[side].duplicate(true)
	elif shared_only:
		s.back = draft.back.duplicate(true)
	else:
		var found = false
		for i in s.cards.size():
			if s.cards[i].id == original_id:
				s.cards[i] = draft.duplicate(true)
				found = true
				break
		if not found:
			s.cards.append(draft.duplicate(true))
		Store.propagate_hidden(series_id,draft.id)
	if Store.commit(before):
		dirty = false
		notify.emit("已保存")
		closed.emit()
	else:
		notify.emit(Store.last_error)

func request_close() -> void:
	if not dirty:
		closed.emit()
		return
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "放弃未保存的修改？"
	dialog.ok_button_text = "放弃"
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free(); closed.emit())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
