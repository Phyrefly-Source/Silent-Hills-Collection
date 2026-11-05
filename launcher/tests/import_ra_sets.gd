extends SceneTree
## Dev tool: turns saved RetroAchievements API_GetGameExtended answers
## (<set id>.json each) into the built-in lists, data/achievements/ra/<set id>.json.
##   godot --headless -s tests/import_ra_sets.gd -- <folder with the saved answers>
## Only the list itself is kept (titles, descriptions, points, badges, rules).
func _initialize() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var RA = load("res://core/achievements/ra.gd")
	var bad := 0
	var patches := []
	for f in DirAccess.get_files_at(dir):
		if not f.get_extension() in ["json", "txt", "htm", "html"]:
			continue
		var txt := FileAccess.get_file_as_string(dir.path_join(f))
		# A browser's "save page" may wrap the JSON in HTML.
		var a := txt.find("{")
		var b := txt.rfind("}")
		var res = JSON.parse_string(txt.substr(a, b - a + 1)) if a >= 0 and b > a else null
		if res is Dictionary and res.has("PatchData"):
			patches.append(res.PatchData)
			continue
		if not res is Dictionary or not res.has("Achievements"):
			print("SKIP ", f, " (not a set)")
			bad += 1
			continue
		var gid := int(res.get("ID", f.get_basename().to_int()))
		var s: Dictionary = RA.parse(gid, res)
		s["source"] = "RetroAchievements set %d (retroachievements.org/game/%d)" % [gid, gid]
		var out := FileAccess.open("res://data/achievements/ra/%d.json" % gid, FileAccess.WRITE)
		out.store_string(JSON.stringify(s, "\t", false))
		out.close()
		var with_rules: int = s.achievements.filter(func(x): return str(x.memaddr) != "").size()
		print("%d %s (%s): %d achievements, %d with rules, %d points" % [gid, s.title, s.console, s.achievements.size(), with_rules,
			s.achievements.reduce(func(t, x): return t + int(x.points), 0)])
	# Emulator feeds (dorequest.php?r=patch) carry the real rules: add them.
	for pd in patches:
		var gid := int(pd.get("ID", 0))
		var path := "res://data/achievements/ra/%d.json" % gid
		var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		if s.is_empty():
			s = RA.parse(gid, {"ID": gid, "Title": pd.get("Title", ""), "ConsoleID": pd.get("ConsoleID", 0), "Achievements": []})
		var rules := {}
		for a in pd.get("Achievements", []):
			if int(a.get("Flags", 3)) == 3:   # core set, not unofficial
				rules[int(a.ID)] = str(a.get("MemAddr", ""))
		var n := 0
		for a in s.achievements:
			if rules.has(int(a.id)) and rules[int(a.id)] != "":
				a.memaddr = rules[int(a.id)]
				n += 1
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(s, "\t", false))
		out.close()
		print("%d: rules added for %d of %d" % [gid, n, s.achievements.size()])
	quit(1 if bad else 0)
