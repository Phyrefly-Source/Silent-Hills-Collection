extends Node
## Achievements: one system for every game, shaped like Steam's.
##
## Each game has one list, data/achievements/<game>.json (made by
## tools/build_achievements.py): the official list where the game had one
## (Steam, PlayStation trophies, Xbox 360), otherwise the RetroAchievements
## community's set. Every entry has a name, a description, an icon, whether
## it's hidden until unlocked, and how many players have it (rarity).
##
## What's unlocked lives in data/achievements/progress.json, whatever unlocked
## it. Each entry's "unlock" says what can:
##   steam    the Steam client's records on this PC (Steam games)
##   ra       a native build running the RetroAchievements set's own rules
##   rexglue  DownpourRecomp's runtime
##   event    events sent through the bridge by Enhanced patches and rebuilds
##   all      every other entry unlocked (the "platinum")
## Any entry can also be unlocked through the bridge by id, or by hand.
##
## Bridge messages are one JSON object per file (or per line) in
## data/achievements/inbox/*.json:
##   {"game":"sh3","event":"leonard_defeated"}   counts an event
##   {"game":"sh3","event":"kills","count":5}    adds to a counter
##   {"game":"sh3","set":"kills","value":40}     sets a counter
##   {"game":"sh3","unlock":"flame-on"}          unlocks an entry by id
##   {"game":"origins","unlock":"ra:12345"}      a RetroAchievements id
## Games started from the launcher get SILENTHILLS_GAME_ID and
## SILENTHILLS_ACHIEVEMENTS_INBOX in their environment.

## An entry was unlocked: the item as view() gives it.
signal earned(game_id: String, item: Dictionary)
signal unlocked(game_id: String, name: String)
signal changed(game_id: String)

var _progress := {}
var _summary := {}     # id -> {unlocked, total}
var _lists := {}       # id -> list (cached)
var _steam_seen := {}  # id -> {entry id: at} from the last Steam read
var _inbox_timer: Timer
var Steam = preload("res://core/achievements/steam_stats.gd")
var Rex = preload("res://core/achievements/rexglue.gd")


func _ready() -> void:
	_progress = App.read_json(_progress_path(), {})
	_summary = App.read_json(App.cache_dir.path_join("achievement-summary.json"), {})
	_inbox_timer = Timer.new()
	_inbox_timer.wait_time = 2.0
	_inbox_timer.autostart = true
	_inbox_timer.timeout.connect(_poll_inbox)
	add_child(_inbox_timer)


## The signed-in profile's progress, or the shared one for Guest.
func _progress_path() -> String:
	var d: String = App.svc("accounts").profile_dir()
	return d.path_join("achievements.json") if d != "" else App.data_dir.path_join("achievements/progress.json")


## Another profile signed in (or out): load its progress.
func reload() -> void:
	_progress = App.read_json(_progress_path(), {})
	_steam_seen.clear()
	_summary.clear()
	for g in App.games:
		view(g.id, func(_groups): changed.emit(g.id))


func _gp(id: String) -> Dictionary:
	if not _progress.has(id):
		_progress[id] = {}
	for k in ["unlocked", "counters", "rexglue", "ra"]:
		if not _progress[id].has(k):
			_progress[id][k] = {}
	return _progress[id]


func _save() -> void:
	App.write_json(_progress_path(), _progress)


## Every platform's list is called Achievements in the launcher.
func term(_id: String = "") -> String:
	return "Achievements"


## Last known {unlocked, total} for the game page, without any work.
func summary(id: String) -> Dictionary:
	return _summary.get(id, {})


## The game's list: {game, platform, source, credit, link, notes, achievements: [...]}.
## Entries you add yourself (data/achievements/<game>.json in the data folder)
## are added after the built-in ones.
func list_def(id: String) -> Dictionary:
	if _lists.has(id):
		return _lists[id]
	var base: Dictionary = App.read_json("res://data/achievements/%s.json" % id, {})
	var user: Dictionary = App.read_json(App.data_dir.path_join("achievements/%s.json" % id), {})
	var by_id := {}
	var order := []
	for a in base.get("achievements", []) + user.get("achievements", []):
		if not by_id.has(a.id):
			order.append(a.id)
		by_id[a.id] = a
	for r in user.get("removed", []):
		by_id.erase(r)
	var d := base.duplicate()
	d.erase("achievements")
	d.achievements = order.filter(func(k): return by_id.has(k)).map(func(k): return by_id[k])
	_lists[id] = d
	return d


func has_list(id: String) -> bool:
	return not list_def(id).achievements.is_empty()


func _entry(id: String, ach_id: String) -> Dictionary:
	for a in list_def(id).achievements:
		if str(a.id) == ach_id:
			return a
	return {}


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000)


static func _xid(v) -> int:
	var s := str(v)
	return s.substr(2).hex_to_int() if s.begins_with("0x") else s.hex_to_int()


static func _norm(s: String) -> String:
	return RegEx.create_from_string("[^a-z0-9]").sub(s.to_lower(), "", true)


# ------------------------------------------------------------------ unlocking
## {entry id: unix ms} for everything unlocked, from every source.
func _unlocked_map(id: String) -> Dictionary:
	var gp := _gp(id)
	var out: Dictionary = gp.unlocked.duplicate()
	for a in list_def(id).achievements:
		if out.has(a.id):
			continue
		var u: Dictionary = a.get("unlock", {})
		match str(u.get("type", "")):
			"ra":
				var k := str(int(u.get("id", 0)))
				if gp.ra.has(k):
					out[a.id] = {"at": int(gp.ra[k]) * 1000, "via": "native"}
			"steam":
				if _steam_seen.get(id, {}).has(a.id):
					out[a.id] = {"at": int(_steam_seen[id][a.id]) * 1000, "via": "steam"}
	return out


## Unlocks one entry (once). Returns true when it was newly unlocked.
func unlock(id: String, ach_id: String, via: String, at_ms: int = 0, quiet: bool = false) -> bool:
	var a := _entry(id, ach_id)
	if a.is_empty() or _unlocked_map(id).has(ach_id):
		return false
	_gp(id).unlocked[ach_id] = {"at": at_ms if at_ms > 0 else _now_ms(), "via": via}
	if not quiet:
		_announce(id, a)
	return true


func _announce(id: String, a: Dictionary) -> void:
	var item := _item(a, {"at": _now_ms()})
	earned.emit(id, item)
	unlocked.emit(id, str(a.name))


## Re-checks entries that don't need the game running. Returns names newly unlocked.
func _evaluate_list(id: String, quiet: bool) -> Array:
	var d := list_def(id)
	if d.achievements.is_empty():
		return []
	var gp := _gp(id)
	var gs := App.state(id)
	var rex_read := false
	var newly := []
	for a in d.achievements:
		var u: Dictionary = a.get("unlock", {})
		var hit := false
		var at := 0
		match str(u.get("type", "")):
			"rexglue":
				if not rex_read and str(gs.get("path", "")) != "":
					for xid in Rex.read(gs.path):
						if not gp.rexglue.has(str(xid)):
							gp.rexglue[str(xid)] = Rex.last_result.get(xid, _now_ms())
					rex_read = true
				var k := str(_xid(u.get("id", "0")))
				if gp.rexglue.has(k):
					hit = true
					at = int(gp.rexglue[k])
			"event":
				hit = int(gp.counters.get(str(u.get("name", a.id)), 0)) >= int(u.get("count", 1))
			"stat":
				var v := int(gs.get("playtime", 0)) if u.get("stat", "playtime") == "playtime" else int(gs.get("sessions", 0))
				hit = v >= int(u.get("value", 0))
		if hit and unlock(id, a.id, str(u.type), at, true):
			newly.append(a)
	# The "platinum": everything else unlocked.
	var have := _unlocked_map(id)
	for a in d.achievements:
		if str(a.get("unlock", {}).get("type", "")) == "all" and not have.has(a.id):
			var rest: Array = d.achievements.filter(func(x): return x.id != a.id)
			if not rest.is_empty() and rest.all(func(x): return have.has(x.id)):
				if unlock(id, a.id, "all", 0, true):
					newly.append(a)
	if not newly.is_empty() or rex_read:
		_save()
	if not quiet:
		for a in newly:
			_announce(id, a)
	return newly.map(func(a): return a.name)


func refresh(id: String) -> void:
	_evaluate_list(id, false)
	changed.emit(id)


## Marks an entry by hand (or clears it).
func set_unlocked(id: String, ach_id: String, on: bool) -> void:
	var gp := _gp(id)
	if on:
		gp.unlocked[ach_id] = {"at": _now_ms(), "via": "manual"}
	else:
		gp.unlocked.erase(ach_id)
		var u: Dictionary = _entry(id, ach_id).get("unlock", {})
		if str(u.get("type", "")) == "ra":
			gp.ra.erase(str(int(u.get("id", 0))))
	_evaluate_list(id, true)
	_save()
	changed.emit(id)


func mark(id: String, _source: String, ach_id: String, on: bool) -> void:
	set_unlocked(id, ach_id, on)


# ------------------------------------------------------------------ bridge
func _poll_inbox() -> void:
	var dir := App.data_dir.path_join("achievements/inbox")
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if not (f.ends_with(".json") or f.ends_with(".txt")):
			continue
		var p := dir.path_join(f)
		var txt := FileAccess.get_file_as_string(p)
		if DirAccess.remove_absolute(p) != OK:
			continue   # still being written; next time
		var lines := [txt] if not txt.strip_edges().contains("\n") else txt.split("\n", false)
		for line in lines:
			handle_message(str(line))


func handle_message(line: String) -> Dictionary:
	var s := line.strip_edges()
	if s == "":
		return {"ok": false}
	var msg = JSON.parse_string(s) if s.begins_with("{") else null
	if msg == null:
		var parts := s.split(" ", false)
		if parts.size() < 2:
			return {"ok": false}
		msg = {parts[0]: parts[1], "game": parts[2] if parts.size() > 2 else ""}
	var id := str(msg.get("game", ""))
	if id == "":
		var running: Array = App.svc("runner").sessions.keys()
		if running.size() == 1:
			id = running[0]
	if App.game(id).is_empty():
		return {"ok": false, "error": "unknown game"}
	var gp := _gp(id)
	if msg.has("event"):
		gp.counters[msg.event] = int(gp.counters.get(msg.event, 0)) + int(msg.get("count", 1))
	if msg.has("set"):
		gp.counters[msg.set] = int(msg.get("value", 0))
	if msg.has("unlock"):
		var key := str(msg.unlock)
		if key.begins_with("ra:"):
			# A native build ran a RetroAchievements set (dev/silenthills-ra).
			var n := key.substr(3)
			if not gp.ra.has(n):
				gp.ra[n] = int(Time.get_unix_time_from_system())
				var a := {}
				for x in list_def(id).achievements:
					var u: Dictionary = x.get("unlock", {})
					if str(u.get("type", "")) == "ra" and str(int(u.get("id", 0))) == n:
						a = x
				if not a.is_empty():
					_announce(id, a)
		else:
			unlock(id, key, "bridge")
	_save()
	_evaluate_list(id, false)
	changed.emit(id)
	return {"ok": true}


# ------------------------------------------------------------------ view
## One entry as shown everywhere (launcher, companion app):
## {id, name, description, icon, icon_locked, unlocked, at (unix s), hidden,
##  rarity (% of players, -1 unknown), grade, via, source}
func _item(a: Dictionary, u: Dictionary) -> Dictionary:
	var on := not u.is_empty()
	var icon := str(a.get("icon", ""))
	if not on and str(a.get("icon_locked", "")) != "":
		icon = str(a.icon_locked)
	return {"id": str(a.id), "name": str(a.name), "description": str(a.get("description", "")), "icon": icon,
		"icon_unlocked": str(a.get("icon", "")), "locked_art": str(a.get("icon_locked", "")) != "",
		"unlocked": on, "at": int(u.get("at", 0)) / 1000, "hidden": bool(a.get("hidden", false)),
		"rarity": float(a.get("rarity", -1.0)), "grade": str(a.get("grade", "")), "via": str(u.get("via", "")),
		"points": 0, "source": "list"}


## Builds the game's achievements. cb([group]) with one group (or none):
## {source, title, platform, credit, link, note, unlocked, total, items: [item]}.
func view(id: String, cb: Callable, _force: bool = false) -> void:
	var d := list_def(id)
	if d.achievements.is_empty():
		_summary.erase(id)
		cb.call([])
		return
	var finish := func():
		_evaluate_list(id, true)
		var have := _unlocked_map(id)
		var items := []
		for a in d.achievements:
			items.append(_item(a, have.get(a.id, {})))
		var u := items.filter(func(i): return i.unlocked).size()
		_summary[id] = {"unlocked": u, "total": items.size()}
		App.write_json(App.cache_dir.path_join("achievement-summary.json"), _summary)
		cb.call([{"source": "list", "order": 0, "title": str(d.get("source", "Achievements")),
			"platform": str(d.get("platform", "")), "credit": str(d.get("credit", "")), "link": str(d.get("link", "")),
			"note": str(d.get("notes", "")), "rarity_source": str(d.get("rarity_source", "")),
			"items": items, "unlocked": u, "total": items.size()}])
	var appid := str(d.get("steam_appid", ""))
	if appid == "":
		finish.call()
		return
	# Steam games: what's unlocked comes from the Steam client's cache.
	var root: String = App.svc("scanner").steam_root()
	var user: String = App.settings.get("steam_user", "")
	App.run(func(): return Steam.read(root, appid, user, []), func(r):
		_match_steam(id, r)
		finish.call())


## Matches the Steam client's records to the list's entries (by stat key, then name).
func _match_steam(id: String, r: Dictionary) -> void:
	var seen := {}
	if r.get("ok", false):
		var by_key := {}
		var by_name := {}
		for it in r.items:
			if it.unlocked:
				by_name[_norm(str(it.name))] = int(it.at)
		var keys := {}
		for a in list_def(id).achievements:
			var u: Dictionary = a.get("unlock", {})
			if str(u.get("steam_id", "")) != "":
				keys[str(u.steam_id)] = a.id
		for it in r.items:
			if it.unlocked and keys.has(str(it.id)):
				by_key[keys[str(it.id)]] = int(it.at)
		for a in list_def(id).achievements:
			if by_key.has(a.id):
				seen[a.id] = by_key[a.id]
			elif by_name.has(_norm(str(a.name))):
				seen[a.id] = by_name[_norm(str(a.name))]
	var before: Dictionary = _steam_seen.get(id, {})
	_steam_seen[id] = seen
	# Unlocked on Steam since the launcher last looked: announce.
	if _progress.has(id) and _progress[id].has("steam_known"):
		for k in seen:
			if not _progress[id].steam_known.has(k) and not before.has(k):
				var a := _entry(id, k)
				if not a.is_empty():
					_announce(id, a)
	_gp(id).steam_known = seen.keys()
	_save()
