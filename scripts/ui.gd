class_name UI
extends RefCounted

static func style(color: Color, radius = 12, border = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 17
	t.set_color("font_color","Label",Color("e1e9e9"))
	t.set_color("font_color","Button",Color("e1e9e9"))
	t.set_stylebox("normal","Button",style(Color("1b2a33"),10,Color("32454d")))
	t.set_stylebox("hover","Button",style(Color("29424a")))
	t.set_stylebox("pressed","Button",style(Color("35645e")))
	t.set_stylebox("focus","Button",style(Color.TRANSPARENT,10,Color("5ecdb1")))
	t.set_stylebox("disabled","Button",style(Color("131c22")))
	t.set_color("font_disabled_color","Button",Color("637278"))
	t.set_stylebox("normal","LineEdit",style(Color("0d171e"),8,Color("33414d")))
	t.set_stylebox("focus","LineEdit",style(Color("0d171e"),8,Color("65dbb7")))
	t.set_stylebox("normal","TextEdit",style(Color("0d171e"),8,Color("33414d")))
	t.set_stylebox("panel","PanelContainer",style(Color("111d26")))
	t.set_constant("separation","VBoxContainer",10)
	t.set_constant("separation","HBoxContainer",8)
	return t

static func button(parent: Node, text: String, callback: Callable, expand = false) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 46
	b.focus_mode = Control.FOCUS_NONE
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

static func label(parent: Node, text: String, font_size = 17, color = Color("e1e9e9")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func row(parent: Node) -> HBoxContainer:
	var h = HBoxContainer.new()
	parent.add_child(h)
	return h

static func column(parent: Node) -> VBoxContainer:
	var v = VBoxContainer.new()
	parent.add_child(v)
	return v

static func field(parent: Node, value: String, placeholder = "") -> LineEdit:
	var e = LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = 46
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e

static func number(parent: Node, value: float, minimum = 0.0, maximum = 1000000.0, step = 1.0) -> SpinBox:
	var n = SpinBox.new()
	n.min_value = minimum
	n.max_value = maximum
	n.step = step
	n.value = value
	n.custom_minimum_size = Vector2(110,44)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(n)
	return n

static func select(parent: Node, items: Array, selected = 0) -> OptionButton:
	var b = OptionButton.new()
	for item in items:
		b.add_item(str(item))
	b.selected = selected
	b.custom_minimum_size.y = 44
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b

static func spacer(parent: Node) -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

static func clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()

