extends SceneTree
## Every game's list in the one shape; bridge, RA-native and "all" unlocks;
## the unlock popups. Run with SILENTHILLS_ROOT set.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var ach = App.svc("achievements")
	DirAccess.remove_absolute(ach._progress_path())
	ach._progress = {}
	var popups := []
	ach.earned.connect(func(g, it): popups.append("%s: %s (%s, %.1f%%)" % [g, it.name, it.icon_unlocked.get_file(), it.rarity]))
	for g in App.games:
		var done := [false]
		ach.view(g.id, func(groups):
			if groups.is_empty():
				print("%-20s no list" % g.id)
			else:
				var gr: Dictionary = groups[0]
				var no_icon: int = gr.items.filter(func(i): return i.icon == "").size()
				var no_rar: int = gr.items.filter(func(i): return i.rarity < 0).size()
				var hid: int = gr.items.filter(func(i): return i.hidden).size()
				print("%-20s %3d  %d/%d  hidden %d  no icon %d  no rarity %d  | %s · %s" % [g.id, gr.total, gr.unlocked, gr.total, hid, no_icon, no_rar, gr.title, gr.credit])
			done[0] = true)
		while not done[0]:
			await process_frame
	# bridge unlock by id, event, RA native, platinum
	ach.handle_message('{"game":"sh3","unlock":"flame-on"}')
	ach.handle_message('{"game":"homecoming","event":"lock-n-load"}')
	var ra_id: int = ach.list_def("origins").achievements[0].unlock.id
	ach.handle_message('{"game":"origins","unlock":"ra:%d"}' % ra_id)
	for a in ach.list_def("sh2").achievements:
		if a.get("unlock", {}).get("type", "") != "all":
			ach._gp("sh2").unlocked[a.id] = {"at": 1, "via": "test"}
	ach.refresh("sh2")
	print("popups:")
	for p in popups:
		print("  ", p)
	var done := [false]
	ach.view("origins", func(groups):
		var it = groups[0].items.filter(func(i): return i.unlocked)[0]
		print("origins unlocked: ", it.name, " via ", it.via, " icon ", it.icon.get_file())
		var lk = groups[0].items.filter(func(i): return not i.unlocked)[0]
		print("origins locked icon: ", lk.icon.get_file())
		done[0] = true)
	while not done[0]:
		await process_frame
	quit()
