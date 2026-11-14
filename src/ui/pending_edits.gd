extends RefCounted
## Compare editable values against their applied baseline, then collect existing Apply actions.
var groups: Dictionary = {}
var drafts: Dictionary = {}

## Each group owns only the controls handled by its action; untouched groups stay untouched.
func register(key: String, controls: Array, action: Callable, snapshot: Callable = Callable()) -> void:
	var values: Array = []
	for control in controls: values.append(_value(control))
	groups[key] = {"controls": controls, "baseline": values, "action": action, "snapshot": snapshot}
	if drafts.has(key) and drafts[key]["baseline"].size() == values.size():
		for index in controls.size():
			if _equal(values[index], drafts[key]["baseline"][index]): _restore(controls[index], drafts[key]["values"][index])

## Preserve typed values when an unrelated immediate setting rebuilds the inspector.
func capture() -> void:
	for key in groups:
		var group: Dictionary = groups[key]
		if changed(group):
			var values: Array = []
			for control in group["controls"]: values.append(_value(control))
			drafts[key] = {"baseline": group["baseline"], "values": values}
			if group["snapshot"].is_valid(): drafts[key]["command"] = group["snapshot"].call()
		else: drafts.erase(key)

func _equal(value: Variant, baseline: Variant) -> bool:
	return is_equal_approx(value, baseline) if value is float and baseline is float else value == baseline

## Block checkbox signals while restoring fields; restoration is not another edit command.
func _restore(control: Control, value: Variant) -> void:
	control.set_block_signals(true)
	if control is SpinBox:
		control.value = value
		control.get_line_edit().text = str(value)
	elif control is LineEdit: control.text = value
	elif control is ColorPickerButton: control.color = value
	elif control is OptionButton: control.select(value)
	elif control is BaseButton: control.button_pressed = value
	control.set_block_signals(false)

## Invalid controls can belong to an inspector selection which has just been replaced.
func changed(group: Dictionary) -> bool:
	for index in group["controls"].size():
		var control = group["controls"][index]
		if not is_instance_valid(control): return false
		var value: Variant = _value(control)
		var baseline: Variant = group["baseline"][index]
		if value is float and baseline is float:
			if not is_equal_approx(value, baseline): return true
		elif value != baseline: return true
	return false

## Snapshot every action before invocation; the caller captures commands without committing yet.
func collect() -> Array:
	for group in groups.values():
		if changed(group):
			for control in group["controls"]:
				if control is SpinBox: control.apply()
			group["action"].call()
	var inactive: Array = []
	for key in drafts:
		if not groups.has(key) and drafts[key].has("command"): inactive.append(drafts[key]["command"])
	return inactive

## Read typed numeric text before focus loss, while ignoring display-only formatting changes.
func _value(control: Control) -> Variant:
	if control is SpinBox:
		var text: String = control.get_line_edit().text.strip_edges()
		return text.to_float() if text.is_valid_float() else control.value
	if control is LineEdit: return control.text
	if control is ColorPickerButton: return control.color
	if control is OptionButton: return control.selected
	if control is BaseButton: return control.button_pressed
	return null
