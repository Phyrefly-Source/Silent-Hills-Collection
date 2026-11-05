extends SceneTree
## Homecoming Enhanced on the Mods tab: on -> off -> on against a fake game folder in
## SILENTHILLS_ROOT. Off must leave the game exactly as before (files and config values);
## on must bring the patch back with the player's settings.
## Run: SILENTHILLS_ROOT=<tmp> godot --headless --path . -s tests/enhanced_toggle.gd
var fails := 0

func ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var game: String = App.root_dir.path_join("games/Silent Hill Homecoming")
	var stock_vars := "AutoDownResTextures=0\r\nFullScreen=true\r\nmaxlights=8\r\nvolume=1.000000\r\n"
	var stock_default := "vsync=1\r\nvsyncInterval=1\r\n"
	_write(game.path_join("Bin/SilentHill.exe"), "stub")
	_write(game.path_join("Bin/shv.dll"), "unknownproject")
	_write(game.path_join("Engine/vars_pc.cfg"), stock_vars)
	_write(game.path_join("Engine/default_pc.cfg"), stock_default)
	App.set_state("homecoming", {"path": game})
	var routes = App.svc("routes")
	var pkg: Dictionary = routes.package("homecoming")
	ok(pkg.get("kind", "") == "enhanced", "package found: " + str(pkg.get("name", "")))
	var s: Dictionary = routes.status("homecoming")
	ok(s.primary.action == "install_patch", "first: offers Install (" + str(s.primary) + ")")

	# on
	ok(routes.install_patch("homecoming") == "", "install")
	ok(FileAccess.file_exists(game.path_join("Bin/dinput8.dll")), "dll in place")
	ok(FileAccess.file_exists(game.path_join("Enhanced/prompts/pad.nx.a.png")), "prompts in place")
	s = routes.status("homecoming")
	ok(s.patch_installed and s.primary.action == "play", "status on")

	# play: the DLL records the originals and changes values (simulated)
	_write(game.path_join("Enhanced/engine-originals.ini"), "[vars_pc.cfg]\r\nAutoDownResTextures=0\r\nFullScreen=true\r\nmaxlights=8\r\n[default_pc.cfg]\r\nvsync=1\r\n[meta]\r\ncaptured=1\r\n")
	_write(game.path_join("Enhanced/HomecomingEnhanced.ini"), "[Prompts]\r\nStyle=2\r\n[EngineValues]\r\nvars_pc.cfg:maxlights=16\r\n")
	_write(game.path_join("Engine/vars_pc.cfg"), "AutoDownResTextures=1024\r\nFullScreen=false\r\nmaxlights=16\r\nvolume=0.500000\r\n")
	_write(game.path_join("Engine/default_pc.cfg"), "vsync=0\r\nvsyncInterval=1\r\n")

	# off
	ok(routes.remove_patch("homecoming") == "", "remove")
	ok(not FileAccess.file_exists(game.path_join("Bin/dinput8.dll")), "dll gone")
	ok(not DirAccess.dir_exists_absolute(game.path_join("Enhanced/prompts")) or DirAccess.get_files_at(game.path_join("Enhanced/prompts")).is_empty(), "prompts gone")
	ok(FileAccess.file_exists(game.path_join("Bin/shv.dll")), "Patch 3.20 untouched")
	ok(_read(game.path_join("Engine/vars_pc.cfg")) == "AutoDownResTextures=0\r\nFullScreen=true\r\nmaxlights=8\r\nvolume=0.500000\r\n", "config values restored, player's own (volume) kept: " + _read(game.path_join("Engine/vars_pc.cfg")).c_escape())
	ok(_read(game.path_join("Engine/default_pc.cfg")) == stock_default, "vsync restored")
	ok(FileAccess.file_exists(game.path_join("Enhanced/HomecomingEnhanced.ini")), "player's patch settings kept")
	s = routes.status("homecoming")
	ok(not s.patch_installed and s.primary.action == "play", "status off, Play starts the plain game (" + str(s.primary) + ")")

	# on again
	ok(routes.install_patch("homecoming") == "", "install again")
	ok(FileAccess.file_exists(game.path_join("Bin/dinput8.dll")), "dll back")
	ok(_read(game.path_join("Enhanced/HomecomingEnhanced.ini")).contains("Style=2"), "settings still there for the DLL to re-apply")
	s = routes.status("homecoming")
	ok(s.patch_installed, "status on again")
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
