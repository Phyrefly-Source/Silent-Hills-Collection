extends RefCounted
## The console achievement sets for the classic games (originally made by the
## RetroAchievements community), built into the launcher in
## data/achievements/ra/<set id>.json. No account, key or connection needed.
##
##  * Used as the achievement list (with RA's badges) for the games that never
##    had an official one: see tools/build_achievements.py and achievements.gd.
##  * Played natively: native rebuilds that keep the console's memory run the
##    set's own conditions with RetroAchievements' evaluator (the kit in
##    dev/silenthills-ra). When the launcher starts such a game it writes the
##    achievements still locked to a file and passes its path in
##    SILENTHILLS_RA_DEFS; unlocks come back through the bridge inbox as
##    {"unlock": "ra:<id>"} and are recorded by achievements.gd.
##
## Unlocks stay in the launcher (and the companion app); nothing is sent anywhere.
## tests/import_ra_sets.gd turns RetroAchievements' API_GetGameExtended answers
## into the bundled files.

const BADGE := "https://media.retroachievements.org/Badge/%s.png"
const CONSOLES := {12: "PlayStation", 21: "PlayStation 2", 41: "PSP", 19: "Wii", 16: "GameCube"}

var _sets := {}   # set id -> set


## Set ids for a launcher game (games.json "ra.game_ids").
func game_ids(id: String) -> Array:
	return App.game(id).get("ra", {}).get("game_ids", [])


static func _dir() -> String:
	return App.data_dir.path_join("achievements/ra")


## A set: {id, title, console_id, console, achievements: [{id, title, description,
## points, badge, memaddr, type, order}]}, or {} when it isn't built in.
func get_set(gid: int) -> Dictionary:
	if not _sets.has(gid):
		_sets[gid] = App.read_json("res://data/achievements/ra/%d.json" % gid, {})
	return _sets[gid]


static func parse(gid: int, res: Dictionary) -> Dictionary:
	var achs = res.get("Achievements", {})
	var vals: Array = achs.values() if achs is Dictionary else achs
	var out := []
	var hashed := RegEx.create_from_string("^[0-9a-f]{32}$")
	for a in vals:
		# The public web API only gives a fingerprint of each rule, not the rule
		# itself; keep real rules only (they come from the emulator feed).
		var rule := str(a.get("MemAddr", ""))
		if hashed.search(rule):
			rule = ""
		out.append({"id": int(a.get("ID", 0)), "title": str(a.get("Title", "")), "description": str(a.get("Description", "")),
			"points": int(a.get("Points", 0)), "badge": str(a.get("BadgeName", "")), "memaddr": rule,
			"type": str(a.get("Type", "") if a.get("Type", null) != null else ""), "order": int(a.get("DisplayOrder", 0))})
	out.sort_custom(func(x, y): return [x.order, x.id] < [y.order, y.id])
	var cid := int(res.get("ConsoleID", 0))
	return {"id": gid, "title": str(res.get("Title", "")), "console_id": cid,
		"console": str(res.get("ConsoleName", CONSOLES.get(cid, ""))), "achievements": out}


## Unlocks recorded by native builds: {achievement id (String): unix time}.
func native_unlocks(id: String) -> Dictionary:
	var gp: Dictionary = App.svc("achievements")._gp(id)
	if not gp.has("ra"):
		gp.ra = {}
	return gp.ra


## Writes the locked achievements of a game's sets for its native build and
## returns the file's path ("" when there's nothing to run). Uses saved sets
## only, so starting a game never waits for the network.
func write_runtime(id: String) -> String:
	if not App.game(id).get("ra", {}).get("native", false):
		return ""
	var native := native_unlocks(id)
	for gid in game_ids(id):
		var s: Dictionary = get_set(int(gid))
		if s.is_empty():
			continue
		var lines := PackedStringArray()
		lines.append("# Silent Hills: RetroAchievements set %d (%s) for the native build" % [int(gid), s.get("title", "")])
		lines.append("#console\t%d" % int(s.get("console_id", 0)))
		lines.append("#game\t" + id)
		var n := 0
		for a in s.get("achievements", []):
			if native.has(str(int(a.id))) or str(a.memaddr) == "":
				continue
			lines.append("%d\t%d\t%s\t%s" % [int(a.id), int(a.points), str(a.memaddr), str(a.title).replace("\t", " ")])
			n += 1
		if n == 0:
			continue
		var path := _dir().path_join("%d.run.tsv" % int(gid))
		DirAccess.make_dir_recursive_absolute(_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return ""
		f.store_string("\n".join(lines) + "\n")
		f.close()
		return path
	return ""
