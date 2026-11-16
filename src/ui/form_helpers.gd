extends RefCounted
## Small native-control builders shared by the inspector pages.


# Read a dotted document path without creating missing fields.
static func value(data: Dictionary, path: String, fallback: Variant = null) -> Variant:
	var cursor: Variant = data
	for part in path.split("."):
		if not cursor is Dictionary or not cursor.has(part):
			return fallback
		cursor = cursor[part]
	return cursor


# Wrap explanatory text inside the current panel width.
static func text(parent: Node, content: String) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


# Align a label and a horizontally expanding editor.
static func row(parent: Node, caption: String, control: Control) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 84
	label.add_theme_color_override("font_color", Color("a5b5b3"))
	box.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	parent.add_child(box)
	return control


# Use a step-aligned numeric range so untouched values stay unchanged.
static func number(parent: Node, caption: String, initial: float, low: float = -10000, high: float = 10000, step: float = 0.1) -> SpinBox:
	var field := SpinBox.new()
	# Range quantizes from min_value; align it with the step to avoid changing 1.0 into 1.01.
	field.min_value = ceil(low / step) * step
	field.max_value = floor(high / step) * step
	field.step = step
	field.value = initial
	field.custom_minimum_size.x = 88
	field.get_line_edit().add_theme_constant_override("minimum_character_width", 0)
	field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Consecutive numbers share a wrapping row; text/path controls retain full width.
	var flow: HFlowContainer
	if parent.get_child_count() > 0 and parent.get_child(-1) is HFlowContainer and parent.get_child(-1).has_meta("numeric_fields"):
		flow = parent.get_child(-1)
	else:
		flow = HFlowContainer.new()
		flow.set_meta("numeric_fields", true)
		flow.add_theme_constant_override("h_separation", 10)
		parent.add_child(flow)
	var cell := VBoxContainer.new()
	cell.custom_minimum_size.x = 148
	var label := Label.new()
	label.text = caption
	label.tooltip_text = caption
	label.clip_text = true
	label.add_theme_color_override("font_color", Color("a5b5b3"))
	label.add_theme_font_size_override("font_size", 12)
	cell.add_child(label)
	cell.add_child(field)
	flow.add_child(cell)
	return field


# Create a single-line text property.
static func line(parent: Node, caption: String, initial: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = initial
	row(parent, caption, field)
	return field


# Create an enabled-state property.
static func check(parent: Node, caption: String, initial: bool) -> CheckBox:
	var field := CheckBox.new()
	field.text = caption
	field.button_pressed = initial
	parent.add_child(field)
	return field


# Display supported string values without engine instance IDs.
static func choice(parent: Node, caption: String, items: Array, initial: String) -> OptionButton:
	var field := OptionButton.new()
	for item in items:
		field.add_item(str(item))
		field.set_item_metadata(field.item_count - 1, str(item))
		if str(item) == initial:
			field.select(field.item_count - 1)
	var names := {"dynamic": "动态物体", "static": "固定物体", "sensor": "接触感应", "inherit": "跟随全局", "custom": "独立设置", "fixed": "固定镜头", "follow_y": "纵向跟随", "wood": "木音", "bell": "铃音", "click": "轻击", "simulation": "模拟时间", "presentation": "成片时间", "orthogonal": "正交", "perspective": "透视", "gl_compatibility": "OpenGL（兼容）", "forward_plus": "Vulkan（高级）"}
	for index in field.item_count: field.set_item_text(index, names.get(str(items[index]), str(items[index])))
	row(parent, caption, field)
	return field


# Return the selected option's persisted string value.
static func selected(field: OptionButton) -> String:
	return str(field.get_item_metadata(field.selected))


# Edit a color with the native picker.
static func color(parent: Node, caption: String, initial: String) -> ColorPickerButton:
	var field := ColorPickerButton.new()
	field.color = Color(initial)
	field.custom_minimum_size = Vector2(80, 28)
	row(parent, caption, field)
	return field


# Attach an explicit action to a native button.
static func button(parent: Node, caption: String, action: Callable) -> Button:
	var field := Button.new()
	field.text = caption
	field.pressed.connect(action)
	parent.add_child(field)
	return field


# Retire controls before rebuilding a panel from the current document.
static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

## Collapse low-frequency settings and preserve the user's disclosure choices across rebuilds.
static func section(parent: Node, caption: String, opened: bool = true) -> VBoxContainer:
	var owner: Node = parent
	while owner.get_parent() != null and not owner.has_meta("inspector_shell"): owner = owner.get_parent()
	var key := "section_" + str(caption.hash()).replace("-", "n")
	var wrapper := VBoxContainer.new()
	parent.add_child(wrapper)
	var header := Button.new()
	header.text = caption
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.toggle_mode = true
	header.flat = true
	header.tooltip_text = "展开 / 收起"
	header.button_pressed = owner.get_meta(key, opened)
	header.add_theme_font_size_override("font_size", 14)
	wrapper.add_child(header)
	var content := VBoxContainer.new()
	content.visible = header.button_pressed
	wrapper.add_child(content)
	content.set_meta("section_header", header)
	header.icon = _chevron(header.button_pressed)
	header.toggled.connect(func(value):
		content.visible = value
		header.icon = _chevron(value)
		owner.set_meta(key, value))
	return content

## The only custom icon is a geometric disclosure chevron in the control's text color.
static func _chevron(opened: bool) -> ImageTexture:
	var points := "4,6 8,10 12,6" if opened else "6,4 10,8 6,12"
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><polyline points="%s" fill="none" stroke="#a5b5b3" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>' % points)
	return ImageTexture.create_from_image(image)
