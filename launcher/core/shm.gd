extends RefCounted
## Silent Hill Memories (silenthillmemories.net): a long-running fan archive of
## official Silent Hill material, with galleries of each game's and film's
## concept art, wallpapers and posters. Its pages are read at run time and the
## pictures fetched when shown; nothing is bundled. The site asks for credit and
## a link back, so every picture keeps a link to the page it came from.

const SITE := "https://www.silenthillmemories.net/"
const DAY := 86400
const IMG_EXT := ["jpg", "jpeg", "png", "webp", "gif"]

var _galleries := {}   # "folder|kind" -> [pictures]
var _waiting := {}


## The site's folder for a catalogue entry (games.json / films.json "art.shm").
static func folder_of(entry: Dictionary) -> String:
	return str(entry.get("art", {}).get("shm", ""))


static func info_url(folder: String) -> String:
	return SITE + folder + "/info_en.htm"


# ------------------------------------------------------------------ fetching
## All pictures of a kind for a site folder. kind: "art" (concept art),
## "wallpapers" or "posters". cb([{thumb, full, caption, section, page, width}]).
func gallery(folder: String, kind: String, cb: Callable) -> void:
	if folder == "":
		cb.call([])
		return
	var key := folder + "|" + kind
	if _galleries.has(key):
		cb.call(_galleries[key])
		return
	if _waiting.has(key):
		_waiting[key].append(cb)
		return
	_waiting[key] = [cb]
	_pages_of(folder, kind, func(pages: Array):
		_read_pages(pages, kind, [], {}, func(pics: Array):
			_galleries[key] = pics
			var cbs: Array = _waiting.get(key, [])
			_waiting.erase(key)
			for c in cbs:
				if c.is_valid():
					c.call(pics)))


## The gallery pages of a kind, found from the game's info page (its Media
## menu), or the usual page names when the menu can't be read.
func _pages_of(folder: String, kind: String, cb: Callable) -> void:
	var base := SITE + folder + "/"
	Net.get_text(info_url(folder), 7 * DAY, func(html: String):
		var pages := []
		for u in links(html, info_url(folder)):
			if u.begins_with(base) and page_kind(u) == kind and not pages.has(u):
				pages.append(u)
		if pages.is_empty():
			var guesses := {"art": ["art_en.htm", "arts_en.htm", "arts_characters_en.htm", "concept_art_en.htm"],
				"wallpapers": ["wallpapers_en.htm"], "posters": ["posters_en.htm"]}
			for g in guesses.get(kind, []):
				pages.append(base + g)
		cb.call(pages))


## Which kind of gallery a page is, from its file name.
static func page_kind(url: String) -> String:
	var f := url.get_file().to_lower()
	if not f.ends_with("_en.htm"):
		return ""   # pictures and other files are never gallery pages
	if f.contains("wallpaper"):
		return "wallpapers"
	if f.contains("poster"):
		return "posters"
	if RegEx.create_from_string("^(concept_)?arts?(_[a-z0-9_]+)?_en\\.htm$").search(f):
		return "art"
	return ""


## Reads gallery pages one after another, following links to sibling pages of
## the same kind (SH3's art is split into characters, creatures and misc).
func _read_pages(queue: Array, kind: String, out: Array, seen: Dictionary, cb: Callable) -> void:
	while not queue.is_empty() and seen.has(queue[0]):
		queue.pop_front()
	if queue.is_empty() or seen.size() >= 16:
		cb.call(out)
		return
	var url: String = queue.pop_front()
	seen[url] = true
	Net.get_text(url, 7 * DAY, func(html: String):
		if html != "":
			var dir := url.get_base_dir() + "/"
			for u in links(html, url):
				if u.begins_with(dir) and page_kind(u) == kind and not seen.has(u) and not queue.has(u):
					queue.append(u)
			var known := {}
			for p in out:
				known[p.full] = true
			for p in parse_gallery(html, url):
				if not known.has(p.full):
					out.append(p)
		_read_pages(queue, kind, out, seen, cb))


# ------------------------------------------------------------------ parsing
static func _attr(tag: String, name: String) -> String:
	var m := RegEx.create_from_string("(?is)\\b" + name + "\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))").search(tag)
	if m == null:
		return ""
	for g in [2, 3, 4]:
		if m.get_string(g) != "":
			return m.get_string(g).strip_edges()
	return ""


static func _text(html: String) -> String:
	var s := RegEx.create_from_string("(?s)<[^>]*>").sub(html, " ", true)
	s = s.replace("&amp;", "&").replace("&nbsp;", " ").replace("&#39;", "'").replace("&quot;", "\"")
	return RegEx.create_from_string("\\s+").sub(s, " ", true).strip_edges()


## Absolute URL for a link on a page.
static func resolve(href: String, page: String) -> String:
	href = href.strip_edges().replace("&amp;", "&")
	if href.begins_with("http://") or href.begins_with("https://"):
		return href.replace("http://", "https://")
	if href.begins_with("//"):
		return "https:" + href
	var root := page.substr(0, page.find("/", 8))
	if href.begins_with("/"):
		return root + href
	var parts := Array(page.get_base_dir().substr(root.length()).split("/", false))
	for seg in href.split("/"):
		if seg == "..":
			if not parts.is_empty():
				parts.pop_back()
		elif seg != "." and seg != "":
			parts.append(seg)
	return root + "/" + "/".join(parts)


static func links(html: String, page: String) -> Array:
	var out := []
	if html.length() > 1500000 or html.contains(char(0)):
		return out
	for m in RegEx.create_from_string("(?is)<a\\b[^>]*>").search_all(html):
		var h := _attr(m.get_string(), "href")
		if h != "" and not h.begins_with("#") and not h.begins_with("mailto:") and not h.begins_with("javascript:"):
			out.append(resolve(h, page))
	return out


static func _is_image(url: String) -> bool:
	return IMG_EXT.has(url.split("?")[0].get_extension().to_lower())


## Width in a file name or link text ("sh3_04_1600.jpg", "1920 x 1080"), else 0.
static func _width_hint(s: String) -> int:
	var m := RegEx.create_from_string("(\\d{3,4})\\s*[x×]\\s*\\d{3,4}").search(s)
	if m:
		return m.get_string(1).to_int()
	m = RegEx.create_from_string("[_-](\\d{4})\\.[a-z]+$").search(s.get_file())
	return m.get_string(1).to_int() if m else 0


## The pictures on a gallery page: thumbnails ("…/thumbs/…") linked to their
## full-size files ("…/pics/…"), with the nearest headings as their section and
## the alt text as caption. Wallpapers linked at several sizes keep the largest.
static func parse_gallery(html: String, page: String) -> Array:
	if html.length() > 1500000 or html.contains(char(0)):
		return []   # not a gallery page
	var heads := []   # [position, level, text]
	for m in RegEx.create_from_string("(?is)<h([1-6])\\b[^>]*>(.*?)</h\\1>").search_all(html):
		var t := _text(m.get_string(2))
		if t != "":
			heads.append([m.get_start(), m.get_string(1).to_int(), t])
	var imgs := RegEx.create_from_string("(?is)<img\\b[^>]*>").search_all(html)
	var anchors := RegEx.create_from_string("(?is)<a\\b[^>]*>(.*?)</a>").search_all(html)
	var out := []
	for i in imgs.size():
		var tag: String = imgs[i].get_string()
		var src := _attr(tag, "src")
		if src == "" or not (src.contains("thumb") or src.contains("/thumbs/")):
			continue
		var start: int = imgs[i].get_start()
		var next_img: int = imgs[i + 1].get_start() if i + 1 < imgs.size() else html.length()
		var thumb := resolve(src, page)
		# Full-size links: the anchor around the thumbnail, plus size links after it.
		var best := ""
		var best_w := -1
		for a in anchors:
			var a_start: int = a.get_start()
			var a_end: int = a.get_end()
			var wraps: bool = a_start <= start and a_end >= imgs[i].get_end()
			var follows: bool = a_start > start and a_start < next_img
			if not (wraps or follows):
				continue
			var href := _attr(a.get_string(), "href")
			if href == "":
				continue
			var full := resolve(href, page)
			if not _is_image(full):
				continue
			var w := _width_hint(full + " " + _text(a.get_string(1)))
			if w > best_w:
				best_w = w
				best = full
		if best == "":
			best = thumb.replace("/thumbs/", "/pics/")
		# Section: the closest heading above the picture.
		# Headings below the page title (h1) nest: "Renders · Heather".
		var stack := {}
		for h in heads:
			if h[0] > start:
				break
			stack[h[1]] = h[2]
			for lv in range(h[1] + 1, 7):
				stack.erase(lv)
		var parts := []
		for lv in range(2, 7):
			if stack.has(lv):
				parts.append(stack[lv])
		var section := " · ".join(parts.slice(-2)) if not parts.is_empty() else str(stack.get(1, ""))
		var cap := _attr(tag, "alt")
		if cap == "":
			cap = _attr(tag, "title")
		if cap == "" or cap.to_lower().ends_with("wallpaper") or cap.to_lower() == "image":
			cap = section if section != "" else best.get_file().get_basename().replace("_", " ")
		out.append({"thumb": thumb, "full": best, "caption": cap, "section": section,
			"page": page, "width": maxi(best_w, 0)})
	return out


# ------------------------------------------------------------------ key art
## A background picture: official key art or the widest wallpaper.
## cb(url) or cb("").
func key_art(folder: String, cb: Callable) -> void:
	gallery(folder, "wallpapers", func(walls: Array):
		gallery(folder, "art", func(art: Array):
			var best := ""
			var best_score := -1000.0
			for p in walls + art:
				var s := _key_score(p, walls.has(p))
				if s > best_score:
					best_score = s
					best = p.full
			cb.call(best if best_score > 0.0 else "")))


static func _key_score(p: Dictionary, wallpaper: bool) -> float:
	var file := str(p.full).get_file().to_lower()
	var sec := str(p.section).to_lower()
	var n := file + " " + sec + " " + str(p.caption).to_lower()
	if file.contains("logo") or file.contains("icon") or file.contains("sketch") or sec.contains("sketch"):
		return -1000.0
	if file.contains("femark") or file.contains("fan"):
		return -1000.0   # wallpapers the site's own designers made, not official art
	var s := 0.0
	if wallpaper:
		s += 2.0 + minf(float(p.width), 3840.0) / 1000.0
		if p.width >= 1920:
			s += 2.0
	if n.contains("key art") or n.contains("key_art") or n.contains("keyart") or n.contains("key visual"):
		s += 6.0
	elif not wallpaper:
		# No key art or wallpaper: a scene from the art pages is the next best thing.
		for w in ["environment", "location", "background", "scenery", "landscape", "town", "promo"]:
			if sec.contains(w):
				s += 0.5
				break
	if n.contains("cover") or n.contains("magazine") or n.contains("box"):
		s -= 4.0
	return s
