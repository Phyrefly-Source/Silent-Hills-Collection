extends RefCounted
## Steam achievements from the Steam client's own local cache (no key needed):
##   <Steam>/appcache/stats/UserGameStatsSchema_<appid>.bin   names, descriptions, icons
##   <Steam>/appcache/stats/UserGameStats_<accountid>_<appid>.bin   unlock bits and times
## Both are binary KeyValues. Icons come from Steam's image server.

const ID64_BASE := 76561197960265728
const CDN := "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/%s/%s"


static func parse_binary(buf: PackedByteArray, pos: int = 0) -> Array:
	var out := {}
	while pos < buf.size():
		var t := buf[pos]
		pos += 1
		if t == 0x08 or t == 0x0B:
			return [out, pos]
		var e := pos
		while e < buf.size() and buf[e] != 0:
			e += 1
		var key := buf.slice(pos, e).get_string_from_utf8()
		pos = e + 1
		var val = null
		match t:
			0x00:
				var r := parse_binary(buf, pos)
				val = r[0]
				pos = r[1]
			0x01:
				var e2 := pos
				while e2 < buf.size() and buf[e2] != 0:
					e2 += 1
				val = buf.slice(pos, e2).get_string_from_utf8()
				pos = e2 + 1
			0x02:
				val = buf.decode_s32(pos)
				pos += 4
			0x03:
				val = buf.decode_float(pos)
				pos += 4
			0x04, 0x06:
				val = buf.decode_u32(pos)
				pos += 4
			0x07, 0x0A:
				val = buf.decode_s64(pos)
				pos += 8
			_:
				return [out, buf.size()]
		out[key] = val
	return [out, pos]


static func parse_text(txt: String) -> Dictionary:
	var re := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"|([{}])")
	var stack: Array = [{}]
	var key = null
	for m in re.search_all(txt):
		var brace := m.get_string(2)
		if brace == "{":
			var d := {}
			stack[-1][str(key)] = d
			stack.append(d)
			key = null
		elif brace == "}":
			if stack.size() > 1:
				stack.pop_back()
		else:
			var s := m.get_string(1)
			if key == null:
				key = s
			else:
				stack[-1][key] = s
				key = null
	return stack[0]


static func users(root: String) -> Array:
	var p := root.path_join("config/loginusers.vdf")
	if not FileAccess.file_exists(p):
		return []
	var v: Dictionary = parse_text(FileAccess.get_file_as_string(p)).get("users", {})
	var out := []
	for id64 in v:
		var u: Dictionary = v[id64]
		out.append({"id64": id64, "account": str(int(id64) - ID64_BASE), "name": u.get("PersonaName", u.get("AccountName", "")),
			"recent": u.get("MostRecent", "0") == "1"})
	out.sort_custom(func(a, b): return a.recent and not b.recent)
	return out


static func _english(v) -> String:
	if v is Dictionary:
		if v.has("english"):
			return str(v.english)
		for k in v:
			if v[k] is String and v[k] != "":
				return v[k]
		return ""
	return str(v) if v != null else ""


static func schema(root: String, appid: String) -> Array:
	var f := root.path_join("appcache/stats/UserGameStatsSchema_%s.bin" % appid)
	if not FileAccess.file_exists(f):
		return []
	var d: Dictionary = parse_binary(FileAccess.get_file_as_bytes(f))[0]
	var app: Dictionary = d.get(appid, d.values()[0] if not d.is_empty() else {})
	var list := []
	var stats: Dictionary = app.get("stats", {})
	for stat_id in stats:
		var st = stats[stat_id]
		if not st is Dictionary or not st.has("bits"):
			continue
		var tp := str(st.get("type", ""))
		if not (tp in ["ACHIEVEMENTS", "GROUPACHIEVEMENTS", "4", "5"]):
			continue
		for bit in st.bits:
			var a: Dictionary = st.bits[bit]
			var disp: Dictionary = a.get("display", {})
			list.append({"id": a.get("name", "%s_%s" % [stat_id, bit]), "key": "%s:%s" % [stat_id, bit],
				"name": _english(disp.get("name", a.get("name", ""))), "description": _english(disp.get("desc", "")),
				"hidden": str(disp.get("hidden", "0")) == "1",
				"icon": (CDN % [appid, disp.icon]) if disp.has("icon") else "",
				"icon_locked": (CDN % [appid, disp.icon_gray]) if disp.has("icon_gray") else ""})
	return list


## {"stat:bit": unix seconds (0 if unknown)}
static func unlocks(root: String, appid: String, account: String) -> Dictionary:
	var f := root.path_join("appcache/stats/UserGameStats_%s_%s.bin" % [account, appid])
	var out := {}
	if not FileAccess.file_exists(f):
		return out
	var cache: Dictionary = parse_binary(FileAccess.get_file_as_bytes(f))[0].get("cache", {})
	for stat_id in cache:
		var st = cache[stat_id]
		if not st is Dictionary:
			continue
		var data := int(st.get("data", 0)) & 0xFFFFFFFF
		var times: Dictionary = st.get("AchievementTimes", {})
		for bit in 32:
			if data & (1 << bit) or times.has(str(bit)):
				out["%s:%d" % [stat_id, bit]] = int(times.get(str(bit), 0))
	return out


## Everything for one game. user = account id to prefer ("" = whoever has stats).
static func read(root: String, appid: String, user: String = "", built_in: Array = []) -> Dictionary:
	if root == "":
		return {"ok": false, "reason": "Steam wasn't found on this PC."}
	var sc := schema(root, appid)
	if sc.is_empty():
		sc = built_in
	if sc.is_empty():
		return {"ok": false, "reason": "Steam hasn't cached this game's achievements yet. Start it once from Steam."}
	var us := users(root)
	var chosen := {}
	for u in us:
		if u.account == user:
			chosen = u
	if chosen.is_empty():
		for u in us:
			if not unlocks(root, appid, u.account).is_empty():
				chosen = u
				break
	if chosen.is_empty() and not us.is_empty():
		chosen = us[0]
	var un := unlocks(root, appid, chosen.get("account", ""))
	var items := []
	for a in sc:
		var got := un.has(a.key)
		items.append({"id": str(a.id), "name": a.name, "description": a.description, "hidden": a.hidden,
			"icon": a.icon if got or str(a.get("icon_locked", "")) == "" else a.icon_locked, "unlocked": got, "at": un.get(a.key, 0)})
	return {"ok": true, "user": chosen, "users": us, "items": items}
