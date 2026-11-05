extends SceneTree
## Silent Hill Memories parsing against tests/net_fixture.gd (SILENTHILLS_NET_FIXTURES).
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var Net = root.get_node("Net")
	var f = load("res://tests/net_fixture.gd").new()
	f.dir = OS.get_environment("SILENTHILLS_NET_FIXTURES")
	Net.fixture = f.reply
	var shm = App.svc("shm")
	var done := [false]
	shm.gallery("sh3", "art", func(l):
		for p in l: print("ART  ", p.section, " | ", p.caption, " | ", p.full.get_file(), " | ", p.thumb.get_file())
		done[0] = true)
	while not done[0]: await process_frame
	done[0] = false
	shm.key_art("sh3", func(u): print("KEY  ", u); done[0] = true)
	while not done[0]: await process_frame
	done[0] = false
	App.svc("art").get_texture("sh3", "hero", func(t): print("HERO ", t); done[0] = true)
	while not done[0]: await process_frame
	done[0] = false
	App.svc("concept").pictures("film-return", func(l): print("FILM ", l.size()); done[0] = true)
	while not done[0]: await process_frame
	print(shm.resolve("../main/x.htm", "https://www.silenthillmemories.net/sh3/info_en.htm"))
	quit()
