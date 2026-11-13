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
	label.custom_minimum_size.x = 150
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
	field.custom_minimum_size.x = 120
	row(parent, caption, field)
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
		if str(item) == initial:
			field.select(field.item_count - 1)
	row(parent, caption, field)
	return field


# Return the selected option's persisted string value.
static func selected(field: OptionButton) -> String:
	return field.get_item_text(field.selected)


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
