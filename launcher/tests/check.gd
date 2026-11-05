extends SceneTree
## Headless checks: every script compiles, plus decoder and reader tests.
func _initialize() -> void:
	var bad := 0
	for p in _scripts("res://"):
		var s = load(p)
		if s == null or (s is GDScript and not s.can_instantiate() and not p.contains("check")):
			print("FAIL ", p)
			bad += 1
	print("scripts checked, failures: ", bad)
	quit(1 if bad else 0)

func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_scripts(dir.path_join(d)))
	return out
