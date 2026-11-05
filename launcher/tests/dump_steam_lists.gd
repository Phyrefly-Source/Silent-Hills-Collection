extends SceneTree
## Dev tool: writes dev/achievements/source/<game>.json (tools/build_achievements.py turns it into the launcher list) from a Steam
## appcache (UserGameStatsSchema_<appid>.bin). Usage:
##   godot --headless -s tests/dump_steam_lists.gd -- <steam root> game=appid ...
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var Steam = load("res://core/achievements/steam_stats.gd")
	for pair in args.slice(1):
		var kv: PackedStringArray = pair.split("=")
		var list: Array = Steam.schema(args[0], kv[1])
		var out := {"game": kv[0], "platform": "steam", "steam_appid": kv[1],
			"source": "Steam (%d achievements)" % list.size(), "achievements": list}
		var f := FileAccess.open("res://dev/achievements/source/%s.json" % kv[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
		print(kv[0], " ", list.size())
	quit()
