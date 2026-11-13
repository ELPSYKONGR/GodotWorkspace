extends RefCounted
## Atomic file commands let AI control the same service used by native panels.
var service: RefCounted
var root := "res://outputs/control"
var last_error := ""

## Keep command input, processed messages and receipts inside the project drive.
func setup(command_service: RefCounted) -> void:
	service = command_service
	for folder in ["inbox", "processed", "results"]: DirAccess.make_dir_recursive_absolute(root.path_join(folder))
	publish({})

## Execute completed JSON files once, retaining structured results for inspection.
func poll() -> void:
	var directory := DirAccess.open(root.path_join("inbox"))
	var files := directory.get_files()
	files.sort()
	for name in files:
		if not name.ends_with(".json"): continue
		var input := root.path_join("inbox").path_join(name)
		var result_path := root.path_join("results").path_join(name)
		if not FileAccess.file_exists(result_path):
			var parser := JSON.new()
			var result: Dictionary
			if parser.parse(FileAccess.get_file_as_string(input)) != OK or not parser.data is Dictionary: result = {"ok": false, "error": "命令JSON无效"}
			else: result = service.execute(parser.data)
			_write(result_path, result)
		DirAccess.rename_absolute(input, root.path_join("processed").path_join(name))

## Publish current state for AI revision checks without exposing live node references.
func publish(info: Dictionary) -> void:
	_write(root.path_join("scene.current.json"), service.document)
	_write(root.path_join("state.json"), info)

## Atomic replacement prevents the UI or AI from reading half a JSON document.
func _write(path: String, data: Dictionary) -> void:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: last_error = "控制文件写入失败：" + path; push_error(last_error); return
	file.store_string(JSON.stringify(data))
	file.close()
	var error := DirAccess.rename_absolute(temporary, path)
	if error != OK: last_error = "控制文件替换失败：" + path; push_error(last_error)
