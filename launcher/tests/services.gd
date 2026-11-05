extends SceneTree
## End-to-end checks of the services against a fake library in SILENTHILLS_ROOT.
var fails := 0

func ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var root_dir: String = App.root_dir
	print("root ", root_dir)
	# scanner
	var sc = App.svc("scanner")
	var res: Dictionary = sc.scan()
	print("installs ", res.installs.keys(), " steam ", res.steam.keys(), " dumps ", res.dumps.keys())
	ok(res.installs.has("sh3") and res.installs.has("sh2") and res.installs.has("downpour"), "scanner finds installs")
	ok(res.steam.has("sh2-remake") and res.steam.has("homecoming"), "scanner finds steam apps")
	var main_script = load("res://ui/main.gd").new()
	var n: int = main_script.apply_scan(res, false)
	main_script.free()
	ok(n >= 5, "applied %d" % n)
	var routes = App.svc("routes")
	var s3: Dictionary = routes.status("sh3")
	ok(s3.playable and s3.patch_installed and s3.primary.action == "play", "sh3 enhanced status: " + str(s3.primary))
	var sdp: Dictionary = routes.status("downpour")
	ok(sdp.playable, "downpour rebuild playable via existing build: " + str(sdp.primary))
	var so: Dictionary = routes.status("origins")
	ok(so.primary.action == "choose_dump", "origins asks for dump: " + str(so.primary))
	var ss: Dictionary = routes.status("sh2-remake")
	ok(ss.primary.action == "play", "steam remake play")
	# achievements
	var ach = App.svc("achievements")
	var done := [false]
	var got := []
	ach.view("sh2-remake", func(g):
		got.append_array(g)
		done[0] = true)
	while not done[0]:
		await process_frame
	ok(got.size() == 1 and got[0].total == 43 and got[0].unlocked == 25, "steam achievements 25/43: " + str(got.map(func(x): return [x.title, x.unlocked, x.total])))
	done[0] = false
	got.clear()
	ach.view("downpour", func(g):
		got.append_array(g)
		done[0] = true)
	while not done[0]:
		await process_frame
	ok(got.size() == 1 and got[0].total == 41 and got[0].unlocked == 1, "downpour rexglue 1/41: " + str(got.map(func(x): return [x.title, x.unlocked, x.total])))
	# bridge inbox
	var f := FileAccess.open(App.data_dir.path_join("achievements/inbox/t.json"), FileAccess.WRITE)
	f.store_string('{"game":"sh3","unlock":"flame-on"}')
	f.close()
	await create_timer(2.5).timeout
	ok(ach._gp("sh3").unlocked.has("flame-on"), "bridge inbox unlock")
	# music
	var lib = App.svc("music")
	# A ripped AIX in a folder of its own still plays (SH2 bgm_112: 7 layers).
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("OSTs/Ripped"))
	for fn in DirAccess.get_files_at(root_dir.path_join("games/Silent Hill 2/sh2e/sound/adx/hotel")):
		DirAccess.copy_absolute(root_dir.path_join("games/Silent Hill 2/sh2e/sound/adx/hotel").path_join(fn), root_dir.path_join("OSTs/Ripped").path_join(fn))
	done[0] = false
	lib.index(func(): done[0] = true)
	while not done[0]:
		await process_frame
	var albums: Array = lib.albums()
	print("albums ", albums.map(func(a): return [a.title, a.tracks.size()]))
	ok(albums.size() >= 2 and albums[0].kind == "ost", "music index %d tracks" % lib.tracks.size())
	var aix: Array = lib.tracks.filter(func(t): return t.kind == "aix")
	ok(not aix.is_empty() and aix[0].seconds > 20, "aix duration %s" % (aix[0].seconds if not aix.is_empty() else -1))
	# jukebox: an AIX track decodes on its thread
	var jb = root.get_node("Jukebox")
	jb.play_list(aix, 0)
	await create_timer(1.5).timeout
	ok(jb._decoders.size() == 7 and jb.playing, "jukebox plays a 7-layer AIX (%d decoders)" % jb._decoders.size())
	jb.seek(20.0)
	await create_timer(0.5).timeout
	ok(jb._decoders[0].position_seconds() >= 20.0, "seek")
	jb.stop()
	# saves
	var gs: Dictionary = App.state("sh3")
	DirAccess.make_dir_recursive_absolute(gs.path.path_join("savedata"))
	var sf := FileAccess.open(gs.path.path_join("savedata/save1.bin"), FileAccess.WRITE)
	sf.store_string("first")
	sf.close()
	var saves = App.svc("saves")
	ok(saves.backup("sh3", "test") == "", "backup")
	sf = FileAccess.open(gs.path.path_join("savedata/save1.bin"), FileAccess.WRITE)
	sf.store_string("second")
	sf.close()
	var list: Array = saves.list("sh3")
	ok(saves.restore("sh3", list.filter(func(b): return b.label == "test")[0].name) == "", "restore")
	ok(FileAccess.get_file_as_string(gs.path.path_join("savedata/save1.bin")) == "first", "restored content")
	# mods
	var mods = App.svc("mods")
	var md: String = mods.mods_dir("sh3").path_join("TestMod")
	DirAccess.make_dir_recursive_absolute(md.path_join("files/data"))
	var mf := FileAccess.open(md.path_join("files/sh3.exe"), FileAccess.WRITE)
	mf.store_string("MODDED")
	mf.close()
	var before := FileAccess.get_file_as_string(gs.path.path_join("sh3.exe"))
	ok(mods.enable("sh3", "TestMod") == "", "mod enable")
	ok(FileAccess.get_file_as_string(gs.path.path_join("sh3.exe")) == "MODDED", "mod applied")
	ok(mods.disable("sh3", "TestMod") == "", "mod disable")
	ok(FileAccess.get_file_as_string(gs.path.path_join("sh3.exe")) == before, "original restored")
	# comics
	var comics = App.svc("comics")
	App.settings.comic_folders = [root_dir]
	done[0] = false
	comics.scan(func(): done[0] = true)
	while not done[0]:
		await process_frame
	var dying: Array = comics.items.filter(func(i): return i.catalogue == "dying-inside")
	ok(not dying.is_empty() and comics.pages(dying[0]).size() == 4, "comic matched with 4 pages")
	ok(comics.page_image(dying[0], 2) != null, "page decodes")
	# iso identify on a generated PSP-like iso is covered by the scanner; dump identify on cue:
	print("FAILURES ", fails)
	App.flush()
	quit(1 if fails else 0)
