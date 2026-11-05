extends SceneTree
## End-to-end: a set saved for Origins, the native-build kit (dev/silenthills-ra,
## built as /tmp/claude-0/fake_game from test/fake_game.c) unlocking two of
## three, and the launcher recording them. Run with SILENTHILLS_ROOT set.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var ra = App.svc("ra")
	var ach = App.svc("achievements")
	ach._gp("origins").ra.clear()
	var path: String = ra.write_runtime("origins")
	print("defs ", path, "\n", FileAccess.get_file_as_string(path))
	OS.set_environment("SILENTHILLS_RA_DEFS", path)
	OS.set_environment("SILENTHILLS_GAME_ID", "origins")
	OS.set_environment("SILENTHILLS_ACHIEVEMENTS_INBOX", App.data_dir.path_join("achievements/inbox"))
	DirAccess.make_dir_recursive_absolute(App.data_dir.path_join("achievements/inbox"))
	var out := []
	OS.execute("/tmp/claude-0/fake_game", [], out, true)
	print(out)
	ach._poll_inbox()
	var done := [false]
	ach.view("origins", func(groups):
		for g in groups:
			print(g.title, " ", g.unlocked, "/", g.total)
			for it in g.items:
				print("   ", it.name, " unlocked=", it.unlocked, " via=", it.get("via", ""), " icon=", it.icon.get_file())
		done[0] = true)
	while not done[0]: await process_frame
	print("next run: ", FileAccess.get_file_as_string(ra.write_runtime("origins")).split("\n").size() - 1, " lines")
	quit()
