extends SceneTree
## Diagnostic: list what a pack actually contains and inspect project.binary.
##   Godot_console.exe --headless --main-pack <pck> --script <abs path> --audio-driver Dummy

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var files: PackedStringArray = []
	_walk("res://", files)
	print("PACK FILE COUNT: %d" % files.size())
	var total: int = 0
	for path: String in files:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var size: int = f.get_length() if f != null else -1
		if size > 0:
			total += size
		if path.contains("project") or path.contains("audio") or path.contains("models"):
			print("  %9d  %s" % [size, path])
	print("PACK TOTAL BYTES: %d" % total)

	for candidate: String in ["res://project.binary", "res://project.godot"]:
		if not FileAccess.file_exists(candidate):
			print("MISSING: %s" % candidate)
			continue
		var f: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		var head: PackedByteArray = f.get_buffer(24)
		print("HEAD %s: len=%d ascii=%s hex=%s" % [
			candidate, f.get_length(), _ascii(head), _hex(head)])
		f.close()

	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	print("MAIN SCENE SETTING: '%s'" % main_scene)
	print("SETTINGS COUNT: %d" % ProjectSettings.get_property_list().size())
	quit(0)


func _walk(dir_path: String, sink: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var child: String = dir_path.path_join(name)
			if dir.current_is_dir():
				_walk(child, sink)
			else:
				sink.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _ascii(data: PackedByteArray) -> String:
	var text: String = ""
	for index: int in range(mini(data.size(), 16)):
		var value: int = data[index]
		text += char(value) if value >= 32 and value < 127 else "."
	return text


func _hex(data: PackedByteArray) -> String:
	var text: String = ""
	for index: int in range(mini(data.size(), 8)):
		text += "%02x " % data[index]
	return text.strip_edges()
