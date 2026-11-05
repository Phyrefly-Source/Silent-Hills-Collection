extends SceneTree
## Loads every game's menu sounds (core/game_sounds.gd) from game files on this machine and prints
## what was found: count, durations, the default picks and the time each library took.
## Roots: GAME_SOUNDS_<ID> (e.g. GAME_SOUNDS_SH4=/path/to/Silent Hill 4), else the folders below.
##   godot --headless --path . -s tests/game_sounds.gd

const GS := preload("res://core/game_sounds.gd")
const UP := "/mnt/user-data/uploads"
const ROOTS := {
	"sh1": [UP + "/Silent Hill"],
	"sh4": [UP + "/Silent Hill 4"],
	"homecoming": [UP + "/Silent Hill Homecoming"],
	"shattered-memories": [UP + "/Silent Hill Shattered Memories"],
	"pt": [UP + "/P.T"],
}


func _initialize() -> void:
	var failed := 0
	var tested := 0
	for id in ROOTS:
		var roots: Array = ROOTS[id].duplicate()
		var env := OS.get_environment("GAME_SOUNDS_" + id.to_upper().replace("-", "_"))
		if env != "":
			roots.push_front(env)
		var root := ""
		for r in roots:
			if DirAccess.dir_exists_absolute(r):
				root = r
				break
		if root == "":
			print("%-19s skipped (no files)" % id)
			continue
		var t0 := Time.get_ticks_usec()
		var lib: Dictionary = GS.library(id, root)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if lib.is_empty():
			print("%-19s nothing read from %s" % [id, root])
			continue
		tested += 1
		var longest := 0.0
		var shortest := 99.0
		for n in lib:
			var s: AudioStreamWAV = lib[n]
			longest = maxf(longest, s.get_length())
			shortest = minf(shortest, s.get_length())
			if not s is AudioStreamWAV or s.data.is_empty():
				failed += 1
				print("  BAD %s" % n)
		print("%-19s %3d sounds, %.3f..%.3f s, %.0f ms  (%s)" % [id, lib.size(), shortest, longest, ms, root])
		var names := lib.keys()
		var shown := []
		for n in names.slice(0, 12):
			var s: AudioStreamWAV = lib[n]
			shown.append("%s %.2fs %dHz%s" % [n, s.get_length(), s.mix_rate, " st" if s.stereo else ""])
		print("    ", ", ".join(shown), " ..." if names.size() > 12 else "")
		var picks: Dictionary = GS.DEFAULTS.get(id, {})
		for e in ["move", "tab", "select", "back"]:
			var n: String = picks.get(e, "")
			if lib.has(n):
				var s: AudioStreamWAV = lib[n]
				var peak := 0.0
				if s.format == AudioStreamWAV.FORMAT_16_BITS:
					for k in range(0, s.data.size(), 2):
						peak = maxf(peak, absf(s.data.decode_s16(k)))
				print("    %-6s -> %-24s %.3f s, %d Hz%s, peak %.2f" % [e, n, s.get_length(), s.mix_rate, " stereo" if s.stereo else "", peak / 32768.0])
				if peak < 300:
					failed += 1
					print("    FAIL: %s is silent" % n)
			else:
				failed += 1
				print("    FAIL: default %s = %s is not in the library" % [e, n])
	print("tested %d games, %d failures" % [tested, failed])
	quit(1 if failed > 0 else 0)
