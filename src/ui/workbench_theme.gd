extends RefCounted
## One native desktop theme: quiet mineral surfaces, mint actions, readable focus and selection.
const INK := Color("e8eeed")
const MUTED := Color("a5b5b3")
const ACCENT := Color("8de0c5")

## Build consistent states for the native controls; no web assets or runtime dependencies.
static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	result.default_font = font
	result.default_font_size = 14
	for type in ["Label", "Button", "CheckBox", "OptionButton", "MenuButton", "LineEdit", "TextEdit", "PopupMenu", "ItemList"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_pressed_color", type, ACCENT)
		result.set_color("font_disabled_color", type, Color("71817f"))
		result.set_color("font_focus_color", type, INK)
	for type in ["Button", "OptionButton", "MenuButton"]:
		result.set_stylebox("normal", type, box("283633", 5, 10, 6))
		result.set_stylebox("hover", type, box("354641", 5, 10, 6))
		result.set_stylebox("pressed", type, box("284c40", 5, 10, 6))
		result.set_stylebox("disabled", type, box("202c29", 5, 10, 6))
		result.set_stylebox("focus", type, focus())
	for type in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, box("121e1b", 4, 9, 7))
		result.set_stylebox("read_only", type, box("1c2825", 4, 9, 7))
		result.set_stylebox("focus", type, focus())
		result.set_color("font_placeholder_color", type, MUTED)
		result.set_color("caret_color", type, ACCENT)
		result.set_color("selection_color", type, Color("315f50"))
	result.set_stylebox("panel", "TabContainer", box("1c2825", 0, 0, 0))
	result.set_stylebox("panel", "PanelContainer", box("1c2825", 0, 14, 12))
	result.set_stylebox("panel", "PopupMenu", box("25332e", 6, 8, 8))
	result.set_stylebox("hover", "PopupMenu", box("365346", 3, 8, 6))
	result.set_stylebox("panel", "ItemList", box("1c2825", 0, 0, 4))
	result.set_stylebox("selected", "ItemList", box("315448", 4, 7, 7))
	result.set_stylebox("selected_focus", "ItemList", box("315448", 4, 7, 7))
	result.set_stylebox("focus", "ItemList", focus())
	result.set_color("font_selected_color", "ItemList", Color("c3f5e2"))
	result.set_constant("v_separation", "ItemList", 10)
	result.set_constant("h_separation", "ItemList", 8)
	result.set_constant("separation", "VBoxContainer", 9)
	result.set_constant("separation", "HBoxContainer", 8)
	result.set_constant("h_separation", "HFlowContainer", 12)
	result.set_constant("v_separation", "HFlowContainer", 10)
	result.set_color("font_color", "CheckBox", INK)
	result.set_stylebox("focus", "CheckBox", focus())
	return result

## Flat surfaces keep the viewport visually separate from the inspector.
static func box(hex: String, radius: int = 0, horizontal: int = 0, vertical: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(hex)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

## Keyboard focus uses an outline, including buttons without a filled surface.
static func focus() -> StyleBoxFlat:
	var style := box("00000000", 4)
	style.border_color = ACCENT
	style.set_border_width_all(1)
	return style

## Reserve the bright treatment for an actual primary action.
static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box("8de0c5", 5, 14, 7))
	button.add_theme_stylebox_override("hover", box("b5eedb", 5, 14, 7))
	button.add_theme_stylebox_override("pressed", box("69c7a8", 5, 14, 7))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("132a22"))
