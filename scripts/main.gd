extends Control

var stage: CardStage
var content: PanelContainer
var nav: HBoxContainer
var coin_label: Button
var toast_label: Label
var current_page = "货架"
var selected_series = ""
var shelf_page = 0
var editor: CardEditor
var overlay: Control
var toast_timer = 0.0
var last_opened: Array = []
var opening_pack = false

func _ready() -> void:
	theme = UI.theme()
	RenderingServer.set_default_clear_color(Color("0c151c"))
	stage = CardStage.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	stage.pack_selected.connect(open_pack)
	stage.shelf()
	var header = HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 18
	header.offset_right = -18
	header.offset_top = 26
	header.offset_bottom = 78
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	UI.button(header,"☰",settings)
	UI.spacer(header).mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_label = UI.button(header,"",func(): navigate("记账"))
	coin_label.add_theme_color_override("font_color",Color("e8cb8e"))
	content = PanelContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 96
	content.offset_bottom = -104
	add_child(content)
	content.hide()
	nav = HBoxContainer.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_left = 18
	nav.offset_right = -18
	nav.offset_top = -84
	nav.offset_bottom = -22
	add_child(nav)
	for title in ["货架","收藏","设计","记账"]:
		UI.button(nav,title,func(): navigate(title),true)
	toast_label = Label.new()
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -140
	toast_label.offset_bottom = -92
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_stylebox_override("normal",UI.style(Color("25463f")))
	toast_label.hide()
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_label)
	Store.changed.connect(update_balance)
	get_window().files_dropped.connect(func(paths):
		if is_instance_valid(editor):
			for path in paths: editor.import_dropped(path))
	update_balance()
	if not Store.last_error.is_empty(): toast(Store.last_error)

func _process(delta: float) -> void:
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0: toast_label.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if opening_pack: return
		if is_instance_valid(overlay): close_overlay()
		elif is_instance_valid(editor): editor.request_close()
		else: navigate("货架")

func update_balance() -> void:
	coin_label.text = "●  %s" % int(Store.data.coins)

func toast(message: String) -> void:
	toast_label.text = message
	toast_label.show()
	toast_label.move_to_front()
	toast_timer = 3.5

func navigate(page: String) -> void:
	current_page = page
	UI.clear(content)
	content.visible = page != "货架"
	stage.visible = page == "货架"
	stage.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if stage.visible else SubViewport.UPDATE_DISABLED
	for b in nav.get_children():
		b.modulate = Color("70dbba") if b.text == page else Color.WHITE
	match page:
		"货架":
			shelf_page = clampi(shelf_page,0,maxi(0,ceili(Store.data.series.size()/3.0)-1))
			stage.shelf(shelf_page)
			if Store.data.series.size() > 3:
				content.show()
				content.mouse_filter = Control.MOUSE_FILTER_IGNORE
				content.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
				var layout = UI.column(content)
				var space = Control.new()
				space.size_flags_vertical = Control.SIZE_EXPAND_FILL
				space.mouse_filter = Control.MOUSE_FILTER_IGNORE
				layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
				layout.add_child(space)
				var row = UI.row(layout)
				UI.button(row,"‹",func(): shelf_page=maxi(0,shelf_page-1); navigate("货架"))
				UI.spacer(row)
				UI.label(row,"%d / %d" % [shelf_page+1,ceili(Store.data.series.size()/3.0)])
				UI.spacer(row)
				UI.button(row,"›",func(): shelf_page=mini(ceili(Store.data.series.size()/3.0)-1,shelf_page+1); navigate("货架"))
		"设计": series_list()
		"收藏": collection()
		"记账": ledger()
	if page != "货架":
		content.mouse_filter = Control.MOUSE_FILTER_STOP
		content.add_theme_stylebox_override("panel",UI.style(Color("111d26")))

func scroller(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var col = UI.column(scroll)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return col

func thumbnail(parent: Node, layers: Array, width = 72.0) -> CardCanvas:
	var canvas = CardCanvas.new()
	canvas.layers = layers
	canvas.custom_minimum_size = Vector2(width,width*1.4)
	parent.add_child(canvas)
	return canvas

func series_list(query = "") -> void:
	UI.clear(content)
	var col = UI.column(content)
	var bar = UI.row(col)
	var search = UI.field(bar,query,"查找系列")
	UI.button(bar,"＋",func(): edit_series(Store.new_series()))
	var list = scroller(col)
	var populate = func(q):
		UI.clear(list)
		for s in Store.data.series:
			if not q.is_empty() and not s.name.to_lower().contains(q.to_lower()): continue
			var panel = PanelContainer.new()
			list.add_child(panel)
			var row = UI.row(panel)
			thumbnail(row,Store.pack_layers(s))
			var info = UI.column(row)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label = UI.label(info,s.name,20)
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			UI.label(info,"%d 种 · 剩余 %d 张" % [s.cards.size(),Store.stock(s)],14,Color("9bafb8"))
			var buttons = UI.row(info)
			UI.button(buttons,"打开",func(): selected_series=s.id; cards_list(),true)
			UI.button(buttons,"编辑",func(): edit_series(s))
		if list.get_child_count() == 0: UI.label(list,"暂无系列",16,Color("8398a3"))
	populate.call(query)
	search.text_changed.connect(populate)

func cards_list(query = "") -> void:
	var s = Store.series_by_id(selected_series)
	if s.is_empty(): series_list(); return
	UI.clear(content)
	var col = UI.column(content)
	var bar = UI.row(col)
	UI.button(bar,"‹",series_list)
	var search = UI.field(bar,query,"查找卡牌")
	UI.button(bar,"＋",func(): edit_card(Store.new_card()))
	var list = scroller(col)
	var populate = func(q):
		UI.clear(list)
		for c in s.cards:
			if not q.is_empty() and not (c.name+" "+c.grade).to_lower().contains(q.to_lower()): continue
			var panel = PanelContainer.new()
			list.add_child(panel)
			var row = UI.row(panel)
			thumbnail(row,c.front)
			var info = UI.column(row)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var title = UI.label(info,c.name,19)
			title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			UI.label(info,"%s · 剩余 %d 张" % [c.grade,c.remaining],14,Color("bcaa80"))
			var actions = UI.row(info)
			UI.button(actions,"编辑",func(): edit_card(c),true)
			UI.button(actions,"3D",func(): view_cards([c],0,s.back if c.shared_back else c.back))
			UI.button(actions,"×",func(): confirm("删除 %s？" % c.name,func():
				var before = Store.data.duplicate(true)
				Store.series_by_id(selected_series).cards = s.cards.filter(func(card): return card.id != c.id)
				if not Store.commit(before): toast(Store.last_error)
				cards_list()))
		if list.get_child_count() == 0: UI.label(list,"暂无卡牌",16,Color("8398a3"))
	populate.call(query)
	search.text_changed.connect(populate)

func edit_series(original: Dictionary) -> void:
	var s = original.duplicate(true)
	var dialog = new_overlay()
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 18; panel.offset_right = -18; panel.offset_top = 72; panel.offset_bottom = -60
	dialog.add_child(panel)
	var col = scroller(panel)
	var actions = UI.row(col)
	UI.button(actions,"返回",close_overlay,true)
	UI.button(actions,"保存",func():
		if save_series(s): close_overlay(); navigate("设计"),true)
	UI.field(col,s.name,"系列名称").text_changed.connect(func(t): s.name=t)
	var price_row = UI.row(col)
	UI.label(price_row,"每包价格")
	UI.number(price_row,s.price).value_changed.connect(func(v): s.price=int(v))
	var count_row = UI.row(col)
	UI.label(count_row,"每包张数")
	UI.number(count_row,s.pack_size,1,30).value_changed.connect(func(v): s.pack_size=int(v))
	for pair in [["牌包封面","cover"],["牌包背面","pack_back"]]:
		var row = UI.row(col)
		var thumb = thumbnail(row,Store.pack_layers(s,pair[1] == "pack_back"),94)
		var key = pair[1]
		var design_key = "pack_back_layers" if key == "pack_back" else "pack_front_layers"
		var actions_col = UI.column(row)
		actions_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(actions_col,pair[0])
		var controls = UI.row(actions_col)
		UI.button(controls,"导入",func(): pick_image(func(path): s[key]=path; s[design_key]=[]; thumb.set_layers(Store.pack_layers(s,key == "pack_back"))),true)
		UI.button(controls,"设计",func():
			if not save_series(s): return
			close_overlay(); selected_series=s.id; edit_pack_surface(design_key),true)
	if not Store.series_by_id(s.id).is_empty():
		UI.button(col,"编辑系列通用卡背",func():
			if not save_series(s): return
			close_overlay(); selected_series=s.id; edit_shared_back())
		UI.button(col,"删除系列",func(): confirm("删除系列及设计？已收藏的卡牌会保留。",func():
			var before = Store.data.duplicate(true)
			Store.data.series = Store.data.series.filter(func(item): return item.id != s.id)
			if Store.commit(before): close_overlay(); navigate("设计")
			else: toast(Store.last_error)))

func save_series(s: Dictionary) -> bool:
	if s.name.strip_edges().is_empty():
		toast("请输入系列名称")
		return false
	var before = Store.data.duplicate(true)
	var existing = Store.series_by_id(s.id)
	if existing.is_empty(): Store.data.series.append(s.duplicate(true))
	else:
		for key in ["name","price","pack_size","cover","pack_back","pack_front_layers","pack_back_layers"]:
			existing[key] = s.get(key,[] if key.ends_with("layers") else "")
	if Store.commit(before): return true
	toast(Store.last_error)
	return false

func edit_pack_surface(surface: String) -> void:
	editor = CardEditor.new()
	editor.series_id = selected_series
	editor.series_surface = surface
	editor.shared_only = true
	editor.side = "back" if surface == "pack_back_layers" else "front"
	editor.draft = Store.new_card()
	editor.draft.shared_back = false
	editor.draft[editor.side] = Store.pack_layers(Store.series_by_id(selected_series),editor.side == "back").duplicate(true)
	connect_editor()

func edit_card(card: Dictionary) -> void:
	editor = CardEditor.new()
	editor.series_id = selected_series
	editor.original_id = card.id
	editor.draft = card.duplicate(true)
	connect_editor()

func edit_shared_back() -> void:
	editor = CardEditor.new()
	editor.series_id = selected_series
	editor.draft = Store.new_card()
	editor.draft.back = Store.series_by_id(selected_series).back.duplicate(true)
	editor.draft.shared_back = false
	editor.shared_only = true
	editor.side = "back"
	connect_editor()

func connect_editor() -> void:
	add_child(editor)
	editor.image_requested.connect(pick_image)
	editor.notify.connect(toast)
	editor.preview_requested.connect(func(card,back):
		if not editor.series_surface.is_empty():
			var s = Store.series_by_id(editor.series_id).duplicate(true)
			s[editor.series_surface] = card[editor.side].duplicate(true)
			var dialog = new_overlay()
			var view = preview_stage(dialog)
			view.show_pack(s)
			if editor.side == "back": view.item.rotation.y=PI-0.2
			UI.button(overlay_bar(dialog),"‹",close_overlay)
		else:
			view_cards([card],0,back)
			if editor.side == "back": overlay.get_child(1).item.rotation.y=PI-0.2)
	editor.closed.connect(func():
		editor.queue_free(); editor=null
		if selected_series.is_empty(): series_list()
		else: cards_list())

func collection() -> void:
	var col = UI.column(content)
	var search = UI.field(col,"","查找名称 / 系列 / 评级")
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",14)
	scroll.add_child(grid)
	var populate = func(query):
		UI.clear(grid)
		var filtered: Array = []
		for card in Store.data.owned:
			if query.is_empty() or (card.name+" "+card.series_name+" "+card.grade).to_lower().contains(query.to_lower()): filtered.append(card)
		filtered.reverse()
		for i in filtered.size():
			var card = filtered[i]
			var slot = UI.column(grid)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(120,168)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.add_child(btn)
			var art = thumbnail(btn,card.front,120)
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			btn.pressed.connect(func(): view_cards(filtered,i))
			var label = UI.label(slot,card.grade,13,Color("d8c18e"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if filtered.is_empty(): UI.label(grid,"暂无卡牌",16,Color("8398a3"))
	populate.call("")
	search.text_changed.connect(populate)

func ledger() -> void:
	var col = UI.column(content)
	var value = UI.number(col,100,-1000000,1000000)
	var note = UI.field(col,"","备注")
	UI.button(col,"记入",func():
		if int(value.value) == 0: return
		if Store.adjust_coins(int(value.value),note.text.strip_edges()): navigate("记账")
		else: toast(Store.last_error))
	var list = scroller(col)
	for entry in Store.data.ledger:
		var row = UI.row(list)
		var text = UI.column(row)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title = UI.label(text,str(entry.note) if not str(entry.note).is_empty() else "手动记账",17)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UI.label(text,str(entry.time).replace("T"," "),12,Color("849aa5"))
		UI.label(row,"%+d" % int(entry.amount),20,Color("71d8b6") if entry.amount > 0 else Color("d4b083"))

func new_overlay() -> Control:
	close_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var bg = ColorRect.new()
	bg.color = Color(0.025,0.04,0.055,1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	return overlay

func close_overlay() -> void:
	if opening_pack: return
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
		overlay = null

func preview_stage(parent: Control) -> CardStage:
	var view = CardStage.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_top = 120
	view.offset_bottom = -150
	parent.add_child(view)
	return view

func overlay_bar(parent: Control, bottom = false) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	row.offset_left = 24; row.offset_right = -24
	row.offset_top = -110 if bottom else 36
	row.offset_bottom = -48 if bottom else 94
	parent.add_child(row)
	return row

func open_pack(series_id: String) -> void:
	var s = Store.series_by_id(series_id)
	if s.is_empty(): return
	var dialog = new_overlay()
	var view = preview_stage(dialog)
	view.show_pack(s)
	var top = overlay_bar(dialog)
	var back = UI.button(top,"‹",close_overlay)
	UI.spacer(top)
	UI.label(top,s.name,20)
	UI.spacer(top)
	UI.label(top,"%d 张" % s.pack_size,16)
	var bottom = overlay_bar(dialog,true)
	var buy = UI.button(bottom,"拆包  ·  %d" % s.price,func(): pass,true)
	buy.disabled = Store.stock(s) < int(s.pack_size)
	if buy.disabled: buy.text = "库存不足"
	buy.pressed.connect(func():
		if opening_pack: return
		buy.disabled = true
		var result = Store.purchase(series_id)
		if result.has("error"):
			toast(result.error); buy.disabled=false; return
		last_opened = result.cards
		opening_pack = true
		back.disabled = true
		buy.text = "…"
		await view.tear()
		opening_pack = false
		view_cards(last_opened))

func view_cards(cards: Array, index = 0, back: Array = []) -> void:
	if cards.is_empty(): return
	var c = cards[index]
	var dialog = new_overlay()
	var view = preview_stage(dialog)
	view.show_card(c,back)
	var top = overlay_bar(dialog)
	UI.button(top,"‹",close_overlay)
	UI.spacer(top)
	UI.label(top,c.grade,22,Color("e2c48b"))
	UI.spacer(top)
	UI.label(top,"%d / %d" % [index+1,cards.size()],15)
	var bottom = overlay_bar(dialog,true)
	var previous = UI.button(bottom,"‹",func(): view_cards(cards,index-1,back))
	previous.disabled = index == 0
	var name_label = UI.label(bottom,c.name,20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.button(bottom,"翻面",func():
		var tween = view.create_tween()
		tween.tween_property(view.item,"rotation:y",view.item.rotation.y+PI,0.5))
	var next = UI.button(bottom,"›",func(): view_cards(cards,index+1,back))
	next.disabled = index == cards.size()-1

func pick_image(callback: Callable) -> void:
	file_dialog(FileDialog.FILE_MODE_OPEN_FILE,PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.svg,*.bmp,*.tga ; 图片"]),func(path):
		var imported = Store.import_image(path)
		if imported.is_empty(): toast(Store.last_error)
		else: callback.call(imported))

func file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, callback: Callable) -> void:
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = filters
	dialog.use_native_dialog = true
	if mode == FileDialog.FILE_MODE_SAVE_FILE: dialog.current_file="MYCARD-backup.zip"
	add_child(dialog)
	dialog.file_selected.connect(func(path): callback.call(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.9)

func confirm(message: String, callback: Callable) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = message
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360,150))

func settings() -> void:
	var dialog = new_overlay()
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-195; panel.offset_right=195; panel.offset_top=-185; panel.offset_bottom=185
	dialog.add_child(panel)
	var col = UI.column(panel)
	UI.button(col,"返回",close_overlay)
	UI.button(col,"导出备份",func(): file_dialog(FileDialog.FILE_MODE_SAVE_FILE,PackedStringArray(["*.zip ; 备份"]),func(path): toast("已导出" if Store.export_backup(path) else "导出失败")))
	UI.button(col,"恢复备份",func(): file_dialog(FileDialog.FILE_MODE_OPEN_FILE,PackedStringArray(["*.zip ; 备份"]),func(path): confirm("用备份替换当前数据？",func():
		if Store.restore_backup(path): close_overlay(); navigate("货架"); toast("已恢复")
		else: toast(Store.last_error))))
	UI.button(col,"开源许可",show_licenses)
	UI.label(col,"MYCARD  0.1.0",14,Color("8398a3"))
	UI.label(col,"离线存储 · 原图备份",14,Color("8398a3"))

func show_licenses() -> void:
	var dialog = new_overlay()
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left=18; panel.offset_right=-18; panel.offset_top=36; panel.offset_bottom=-24
	dialog.add_child(panel)
	var col = UI.column(panel)
	UI.button(col,"返回",settings)
	var text = TextEdit.new()
	text.editable=false
	text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	text.text=Engine.get_license_text()+"\n\n"+JSON.stringify(Engine.get_copyright_info(),"\t")+"\n\n"+JSON.stringify(Engine.get_license_info(),"\t")
	col.add_child(text)
