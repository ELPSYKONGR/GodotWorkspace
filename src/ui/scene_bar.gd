extends VBoxContainer
## Unified scene files and templates; dialogs send the same commands as the AI bridge.
signal command_requested(op: String, args: Dictionary)
const F = preload("res://src/ui/form_helpers.gd")
const Workspace = preload("res://src/document/scene_workspace.gd")
var current_path := ""
var dirty := false
var title: Label
var type_choice: OptionButton
var examples: CheckBox
var new_dialog: ConfirmationDialog
var unsaved_dialog: ConfirmationDialog
var file_dialog: FileDialog
var pending: Dictionary = {}
var file_action := ""
var awaiting_save := false

## Keep file actions on one row and the full scene identity on a separate line.
func _ready() -> void:
	var row := HFlowContainer.new()
	add_child(row)
	F.button(row, "新建场景", func(): new_dialog.popup_centered(Vector2i(480, 200)))
	F.button(row, "打开场景", func(): _choose_file("open"))
	F.button(row, "保存场景", save)
	F.button(row, "另存为", func(): _choose_file("save"))
	title = F.text(self, "正在加载场景")
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "新建场景"
	new_dialog.ok_button_text = "新建"
	new_dialog.cancel_button_text = "取消"
	add_child(new_dialog)
	var form := VBoxContainer.new()
	new_dialog.add_child(form)
	type_choice = F.choice(form, "场景类型", Workspace.TYPES.values(), "二维")
	examples = F.check(form, "包含示例物体（取消则创建空场景）", true)
	# A single-line hint avoids an oversized minimum height before dialog layout.
	F.text(form, "所有类型共用物体编辑、录制、回放和视频生产。").autowrap_mode = TextServer.AUTOWRAP_OFF
	new_dialog.confirmed.connect(func():
		new_dialog.hide()
		request_replace("scene.new", {"name": Workspace.TYPES.keys()[type_choice.selected], "blank": not examples.button_pressed}))
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = "当前场景尚未保存"
	unsaved_dialog.dialog_text = "先保存当前初始布局，再切换场景？运动轨迹请在回放页单独保存。"
	unsaved_dialog.ok_button_text = "保存并继续"
	unsaved_dialog.cancel_button_text = "取消"
	unsaved_dialog.add_button("不保存并继续", false, "discard")
	unsaved_dialog.confirmed.connect(func():
		unsaved_dialog.hide()
		awaiting_save = true
		save())
	unsaved_dialog.custom_action.connect(func(action: StringName):
		if action == "discard": unsaved_dialog.hide(); _continue_pending())
	unsaved_dialog.canceled.connect(_cancel_pending)
	add_child(unsaved_dialog)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; 场景文件"])
	file_dialog.min_size = Vector2i(780, 480)
	file_dialog.file_selected.connect(_file_selected)
	file_dialog.canceled.connect(_cancel_pending)
	add_child(file_dialog)

## The host owns dirty tracking and file identity; this control only presents them.
func sync(path: String, changed: bool, doc: Dictionary) -> void:
	current_path = path
	dirty = changed
	var name := path.get_file() if not path.is_empty() else str(doc.get("metadata", {}).get("title", "未命名场景"))
	var mode := "二维" if doc.get("world", {}).get("dimension", "2d") == "2d" else ("透视三维" if F.value(doc, "presentation.render.camera.projection", "orthogonal") == "perspective" else "正交三维")
	if doc.get("objects", []).any(func(spec: Dictionary): return spec.has("glass")): mode = "玻璃演示 · 二维"
	if mode == "二维" and F.value(doc, "presentation.render.neon.enabled", false): mode = "荧光 · 二维"
	title.text = "%s%s  |  %s  |  %s" % ["* " if dirty else "", name, mode, path if not path.is_empty() else "未保存到文件"]
	title.tooltip_text = title.text

## Replacing a document is deferred until the user resolves unsaved edits.
func request_replace(op: String, args: Dictionary) -> void:
	pending = {"op": op, "args": args}
	if dirty: unsaved_dialog.popup_centered(Vector2i(600, 160))
	else: _continue_pending()

## Regular save reuses the active file; new scenes use the save picker.
func save() -> void:
	if current_path.is_empty(): _choose_file("save")
	else: command_requested.emit("scene.save", {"path": current_path})

## A failed save must never consume the pending scene switch.
func operation_finished(result: Dictionary) -> void:
	if awaiting_save and result.get("scene_saved", false):
		awaiting_save = false
		_continue_pending()
	elif awaiting_save and not result.get("ok", false): _cancel_pending()

## Native file picker supplies filenames and overwrite confirmation.
func _choose_file(action: String) -> void:
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action == "open" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "打开场景" if action == "open" else "保存场景"
	file_dialog.get_ok_button().text = "打开" if action == "open" else "保存"
	file_dialog.get_cancel_button().text = "取消"
	var directory := ProjectSettings.globalize_path("res://scenes")
	DirAccess.make_dir_recursive_absolute(directory)
	file_dialog.current_dir = current_path.get_base_dir() if not current_path.is_empty() else directory
	file_dialog.current_file = "" if action == "open" else (current_path.get_file() if not current_path.is_empty() else "场景_%s.json" % Time.get_datetime_string_from_system().replace(":", "-"))
	file_dialog.popup_centered_ratio(0.75)

## Open follows the unsaved guard after a file has actually been selected.
func _file_selected(path: String) -> void:
	file_dialog.hide()
	if file_action == "open": request_replace("scene.load", {"path": path})
	else: command_requested.emit("scene.save", {"path": path})

## Clear the pending action before emitting because commands complete synchronously.
func _continue_pending() -> void:
	var action := pending
	pending = {}
	awaiting_save = false
	if not action.is_empty(): command_requested.emit(action["op"], action["args"])

## Canceling either prompt or file selection leaves the current scene intact.
func _cancel_pending() -> void:
	pending = {}
	awaiting_save = false
