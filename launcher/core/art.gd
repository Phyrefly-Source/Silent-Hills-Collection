extends Node
## Art: backgrounds (hero), logos and covers for each game.
##
## Order of preference:
##   1. a picture the player chose (data/art/<game>/<kind>.*)
##   2. Steam's own art cache on this PC (official library art)
##   3. SteamGridDB, fetched at run time with the player's own API key
##   4. Steam's public store art for games that are on Steam
##   5. Silent Hill Memories (silenthillmemories.net): the game's key art or
##      widest official wallpaper
## Nothing is bundled. Results are resized once and cached as WebP in
## data/cache/art, so the page loads instantly next time.

signal art_ready(game_id: String, kind: String)

const API := "https://www.steamgriddb.com/api/v2"
const MAX_W := {"hero": 2560, "logo": 900, "cover": 600}
const MEMORY_SLOTS := 24

var _tex := {}          # "id:kind" -> Texture2D (or null = known missing)
var _order: Array = []  # LRU
var _pending := {}      # key -> [callbacks]


func _cache_file(id: String, kind: String) -> String:
	return App.cache_dir.path_join("art").path_join("%s-%s.webp" % [id, kind])


func _user_file(id: String, kind: String) -> String:
	var d := App.data_dir.path_join("art").path_join(id)
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p := d.path_join("%s.%s" % [kind, ext])
		if FileAccess.file_exists(p):
			return p
	return ""


func enhanced_logo_path(id: String) -> String:
	if id != "homecoming" or App.companion:
		return ""
	var routes = App.svc("routes")
	var pkg: Dictionary = routes.package(id)
	if not routes._patch_installed(id, pkg):
		return ""
	var path: String = App.state(id).get("path", "").path_join("Enhanced/ui/art/title_logo.png")
	return path if FileAccess.file_exists(path) else ""


## cb(texture or null). Never blocks: decoding happens on a worker thread.
func get_texture(id: String, kind: String, cb: Callable) -> void:
	# Patch branding is a temporary override, never written into the original art cache.
	if kind == "logo":
		var logo := enhanced_logo_path(id)
		if logo != "":
			var image := Image.load_from_file(logo)
			if image != null:
				cb.call(ImageTexture.create_from_image(image))
				return
	var key := id + ":" + kind
	if _tex.has(key):
		_touch(key)
		cb.call(_tex[key])
		return
	if _pending.has(key):
		_pending[key].append(cb)
		return
	_pending[key] = [cb]
	var user := _user_file(id, kind)
	if user != "":
		_load_async(key, user, kind, true)
		return
	var cached := _cache_file(id, kind)
	if FileAccess.file_exists(cached):
		_load_async(key, cached, kind, false)
		return
	if App.companion:
		# On the phone, backgrounds come from the paired PC (its own choice of
		# art), else straight from the web.
		if kind == "hero" and App.svc("pc").paired():
			App.svc("pc").get_picture("/api/art/%s/hero" % id, func(p: String):
				if p != "" and Pictures.read(p) != null:
					_load_async(key, p, kind, true)
				else:
					_from_web(id, kind, func(p2: String):
						if p2 == "":
							_deliver(key, null)
						else:
							_load_async(key, p2, kind, true)))
		else:
			_from_web(id, kind, func(p2: String):
				if p2 == "":
					_deliver(key, null)
				else:
					_load_async(key, p2, kind, true))
		return
	# Steam's own library art, unless you chose a picture for this game.
	var steam := _steam_file(id, kind) if str(App.state(id).get("art", {}).get(kind, "")) == "" else ""
	if steam != "":
		_load_async(key, steam, kind, true)
		return
	_from_sgdb(id, kind, func(path: String):
		if path != "":
			_load_async(key, path, kind, true)
			return
		_from_web(id, kind, func(p2: String):
			if p2 == "":
				_deliver(key, null)
			else:
				_load_async(key, p2, kind, true)))


## Keyless sources: Steam's public CDN (for games on Steam), then the wiki.
func _from_web(id: String, kind: String, cb: Callable) -> void:
	var appid := _steam_appid(id)
	var wiki_hero := func():
		if kind != "hero":
			cb.call("")
			return
		App.svc("shm").key_art(App.svc("shm").folder_of(App.entry(id)), func(url: String):
			if url == "":
				cb.call("")
			else:
				Net.get_file(url, cb))
	if appid == "":
		wiki_hero.call()
		return
	var want: String = {"hero": "library_hero.jpg", "logo": "logo.png", "cover": "library_600x900.jpg"}[kind]
	Net.get_file("https://cdn.cloudflare.steamstatic.com/steam/apps/%s/%s" % [appid, want], func(p: String):
		if p != "":
			cb.call(p)
		else:
			wiki_hero.call())


func forget(id: String) -> void:
	for kind in ["hero", "logo", "cover"]:
		_tex.erase(id + ":" + kind)
		DirAccess.remove_absolute(_cache_file(id, kind))


func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)
	while _order.size() > MEMORY_SLOTS:
		_tex.erase(_order.pop_front())


func _load_async(key: String, path: String, kind: String, write_cache: bool) -> void:
	var id := key.split(":")[0]
	var cache := _cache_file(id, kind)
	App.run(func():
		var img := Pictures.read(path)
		if img == null:
			return null
		var max_w: int = MAX_W.get(kind, 2048)
		if img.get_width() > max_w:
			img.resize(max_w, int(img.get_height() * float(max_w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		if write_cache and path != cache:
			DirAccess.make_dir_recursive_absolute(cache.get_base_dir())
			img.save_webp(cache, false, 0.9)
		img.generate_mipmaps()
		return img,
	func(img):
		_deliver(key, ImageTexture.create_from_image(img) if img != null else null))


func _deliver(key: String, tex) -> void:
	_tex[key] = tex
	_touch(key)
	var cbs: Array = _pending.get(key, [])
	_pending.erase(key)
	for cb in cbs:
		if cb.is_valid():
			cb.call(tex)
	var parts := key.split(":")
	art_ready.emit(parts[0], parts[1])


# ------------------------------------------------------------------ Steam cache
func _steam_appid(id: String) -> String:
	var gs := App.state(id)
	var g := App.game(id)
	var a := str(gs.get("steam_appid", ""))
	if a == "":
		a = str(g.get("art", {}).get("steam_appid", g.get("install", {}).get("steam_appid", "")))
	return a


func _steam_file(id: String, kind: String) -> String:
	var appid := _steam_appid(id)
	if appid == "":
		return ""
	var root: String = App.svc("scanner").steam_root()
	if root == "":
		return ""
	var want: String = {"hero": "library_hero.jpg", "logo": "logo.png", "cover": "library_600x900.jpg"}[kind]
	var lc := root.path_join("appcache/librarycache")
	var flat := lc.path_join("%s_%s" % [appid, want])
	if FileAccess.file_exists(flat):
		return flat
	return _find_file(lc.path_join(appid), want, 2)


func _find_file(dir: String, name: String, depth: int) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	if FileAccess.file_exists(dir.path_join(name)):
		return dir.path_join(name)
	if depth > 0:
		for sub in DirAccess.get_directories_at(dir):
			var r := _find_file(dir.path_join(sub), name, depth - 1)
			if r != "":
				return r
	return ""


# ------------------------------------------------------------------ SteamGridDB
func has_key() -> bool:
	return str(App.settings.get("sgdb_key", "")).strip_edges() != ""


func _headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + str(App.settings.sgdb_key).strip_edges()])


func _sgdb_game(id: String, cb: Callable) -> void:
	var gs := App.state(id)
	if int(gs.get("sgdb_id", 0)) > 0:
		cb.call(int(gs.sgdb_id))
		return
	if not has_key():
		cb.call(0)
		return
	var appid := _steam_appid(id)
	var g := App.game(id)
	var url := API + ("/games/steam/" + appid if appid != "" else "/search/autocomplete/" + str(g.art.get("search", g.title)).uri_encode())
	Net.get_json(url, _headers(), 30 * 86400, func(res):
		var gid := 0
		if res is Dictionary and res.get("success", false):
			var d = res.data
			if d is Array and not d.is_empty():
				gid = int(_best_match(d, str(g.art.get("search", g.title))).id)
			elif d is Dictionary:
				gid = int(d.get("id", 0))
		if gid > 0:
			App.set_state(id, {"sgdb_id": gid})
		cb.call(gid))


func _best_match(list: Array, title: String) -> Dictionary:
	var want := title.to_lower().replace(":", "")
	for e in list:
		if str(e.name).to_lower().replace(":", "") == want:
			return e
	return list[0]


func _endpoint(kind: String) -> String:
	return {"hero": "heroes", "logo": "logos", "cover": "grids"}[kind]


## Official pictures for the picker, no key needed: Steam's store art (for
## games on Steam) and Silent Hill Memories' wallpapers, key art and posters.
## cb([{url, thumb, author, title}]).
func official_candidates(id: String, kind: String, cb: Callable) -> void:
	var list := []
	var appid := _steam_appid(id)
	if appid != "":
		var want: String = {"hero": "library_hero.jpg", "logo": "logo.png", "cover": "library_600x900.jpg"}[kind]
		var u := "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/%s" % [appid, want]
		list.append({"url": u, "thumb": u, "author": "Steam", "title": "Steam library art"})
	if kind != "hero":
		cb.call(list)
		return
	var shm = App.svc("shm")
	var folder: String = shm.folder_of(App.entry(id))
	shm.gallery(folder, "wallpapers", func(walls: Array):
		shm.gallery(folder, "posters", func(posters: Array):
			shm.gallery(folder, "art", func(art: Array):
				for p in walls:
					var n := str(p.full).get_file().to_lower()
					if not (n.contains("femark") or n.contains("fan")):
						list.append({"url": p.full, "thumb": p.thumb, "author": "Silent Hill Memories", "title": "Wallpaper"})
				for p in art:
					var n := (str(p.section) + " " + str(p.full).get_file()).to_lower()
					if n.contains("key") or n.contains("promo") or n.contains("poster") or n.contains("banner"):
						list.append({"url": p.full, "thumb": p.thumb, "author": "Silent Hill Memories", "title": str(p.section)})
				for p in posters:
					list.append({"url": p.full, "thumb": p.thumb, "author": "Silent Hill Memories", "title": "Poster"})
				cb.call(list))))


## SteamGridDB pictures (needs the player's API key): cb([{url, thumb, author, title}]).
func sgdb_candidates(id: String, kind: String, cb: Callable) -> void:
	_sgdb_candidates(id, kind, func(list: Array):
		cb.call(list.map(func(c): return {"url": c.url, "thumb": c.thumb, "author": c.author, "title": c.style})))


func _sgdb_candidates(id: String, kind: String, cb: Callable) -> void:
	_sgdb_game(id, func(gid: int):
		if gid <= 0:
			cb.call([])
			return
		var q := "?types=static&nsfw=false&humor=false&epilepsy=false"
		if kind == "cover":
			q += "&dimensions=600x900"
		Net.get_json("%s/%s/game/%d%s" % [API, _endpoint(kind), gid, q], _headers(), 7 * 86400, func(res):
			var out := []
			if res is Dictionary and res.get("success", false) and res.data is Array:
				for e in res.data:
					out.append({"url": e.url, "thumb": e.get("thumb", e.url), "author": e.get("author", {}).get("name", ""),
						"score": int(e.get("score", 0)), "style": e.get("style", "")})
			out.sort_custom(func(a, b): return a.score > b.score)
			cb.call(out)))


func _from_sgdb(id: String, kind: String, cb: Callable) -> void:
	var chosen := str(App.state(id).get("art", {}).get(kind, ""))
	if chosen != "":
		Net.get_file(chosen, cb)
		return
	if not has_key():
		cb.call("")
		return
	_sgdb_candidates(id, kind, func(list: Array):
		if list.is_empty():
			cb.call("")
		else:
			Net.get_file(list[0].url, cb))


## Use a specific picture by its web address (from the picker), or "" to go back to automatic.
func choose(id: String, kind: String, url: String) -> void:
	var art: Dictionary = App.state(id).get("art", {})
	art[kind] = url
	App.set_state(id, {"art": art})
	# A chosen picture replaces one of your own from disk.
	var d := App.data_dir.path_join("art").path_join(id)
	for ext in ["png", "jpg", "jpeg", "webp"]:
		DirAccess.remove_absolute(d.path_join("%s.%s" % [kind, ext]))
	_tex.erase(id + ":" + kind)
	DirAccess.remove_absolute(_cache_file(id, kind))
	art_ready.emit(id, kind)


## Use a picture from disk.
func use_file(id: String, kind: String, path: String) -> void:
	var d := App.data_dir.path_join("art").path_join(id)
	DirAccess.make_dir_recursive_absolute(d)
	for ext in ["png", "jpg", "jpeg", "webp"]:
		DirAccess.remove_absolute(d.path_join("%s.%s" % [kind, ext]))
	DirAccess.copy_absolute(path, d.path_join("%s.%s" % [kind, path.get_extension().to_lower()]))
	_tex.erase(id + ":" + kind)
	DirAccess.remove_absolute(_cache_file(id, kind))
	art_ready.emit(id, kind)
