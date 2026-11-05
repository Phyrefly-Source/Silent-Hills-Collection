extends SceneTree
## Indexes SILENTHILLS_ROOT/OSTs and prints albums, tags and covers.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var lib = App.svc("music")
	print("roots ", lib.soundtrack_roots())
	var done := [false]
	lib.index(func(): done[0] = true)
	while not done[0]:
		await process_frame
	for a in lib.albums():
		print("ALBUM [%s] %s -> game=%s cover=%s" % [a.kind, a.title, a.game, str(a.cover).get_file()])
		for t in a.tracks:
			print("   #%d %s | %s | %.1fs | %s" % [t.get("track", 0), t.title, t.get("artist", ""), t.seconds, t.kind])
	var flac: Dictionary = {}
	for t in lib.tracks:
		if t.kind == "ffmpeg":
			flac = t
	var got := [null]
	lib.convert_with_ffmpeg(flac, func(p): got[0] = p)
	lib.convert_with_ffmpeg(flac, func(p): print("second waiter ", p.get_file()))
	while got[0] == null:
		await process_frame
	print("converted ", got[0], " ", FileAccess.file_exists(got[0]))
	quit()
