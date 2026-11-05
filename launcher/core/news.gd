extends Node
## News: what's new in the Silent Hill series, and where to buy its PC games.
##
##  * Headlines from Google News (a "Silent Hill" search, last 30 days),
##    kept to the series and marked "New entry" when they're about a game being
##    announced, dated, released or remade; "Official" when Konami posted them.
##  * Announcements from Steam for the series' Steam games (patches, events).
##  * Buy on PC: every Silent Hill game sold for PC, at the official stores
##    only (Steam, GOG, Epic Games Store), with the sale price when one of them
##    has it on sale and the full price otherwise. Steam's and GOG's prices
##    come from their own stores; Epic has no public price feed, so its price
##    is CheapShark's reading of the Epic store (links go straight to Epic).
##  * New on PC stores: a Silent Hill store page that wasn't there before (a
##    new game, edition or DLC; "coming soon" ones show their date).
##  * This week in Silent Hill history: release anniversaries.
##
## Checked when the launcher starts and every 3 hours after. A sale, a new
## store page or a new-entry headline that wasn't there before gets a notice
## and a dot on the News tab; opening News clears it.

signal updated
signal unseen_changed(count: int)

const NEWS_URL := "https://news.google.com/rss/search?q=%22Silent+Hill%22+when:30d&hl=en-US&gl=US&ceid=US:en"
const STEAM_NEWS := "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=%s&count=4&feeds=steam_community_announcements"
const STEAM_PRICES := "https://store.steampowered.com/api/appdetails?appids=%s&cc=us&filters=price_overview"
const STEAM_SEARCH := "https://store.steampowered.com/api/storesearch/?term=silent%20hill&cc=us&l=en"
const STEAM_APP := "https://store.steampowered.com/app/%s/"
const STEAM_DETAILS := "https://store.steampowered.com/api/appdetails?appids=%s&cc=us&filters=basic"
const GOG_CATALOG := "https://catalog.gog.com/v1/catalog?query=like:silent%20hill&countryCode=US&currencyCode=USD&locale=en-US&limit=48"
const EPIC_PRICES := "https://www.cheapshark.com/api/1.0/games?ids=%s"
const EPIC_SEARCH := "https://store.epicgames.com/en-US/browse?q=%s&sortBy=relevancy&sortDir=DESC&count=40"
const REFRESH := 3 * 3600
const TTL := 30 * 60

## Every Silent Hill game sold for PC, and where (official stores only).
## steam: app id; gog: product slug; epic: CheapShark game id (for its Epic price).
const SHOP := [
	{"game": "townfall", "steam": "1636440", "gog": "silent_hill_townfall", "epic": "323868", "epic_q": "SILENT HILL Townfall"},
	{"game": "sh-f", "steam": "2947440", "gog": "silent_hill_f", "epic": "299085", "epic_q": "SILENT HILL f"},
	{"game": "sh2-remake", "steam": "2124490", "gog": "silent_hill_2", "epic": "256330", "epic_q": "SILENT HILL 2"},
	{"game": "homecoming", "steam": "19000"},
	{"game": "sh4", "gog": "silent_hill_4_the_room"},
]

## Release days (North America unless noted), for "this week in Silent Hill history".
const HISTORY := [
	[1999, 1, 31, "Silent Hill", "game"], [2001, 9, 24, "Silent Hill 2", "game"], [2003, 8, 5, "Silent Hill 3", "game"],
	[2003, 5, 23, "Silent Hill 3 (Japan)", "game"], [2004, 9, 7, "Silent Hill 4: The Room", "game"],
	[2004, 6, 17, "Silent Hill 4: The Room (Japan)", "game"], [2007, 11, 6, "Silent Hill: Origins", "game"],
	[2008, 9, 30, "Silent Hill: Homecoming", "game"], [2009, 12, 8, "Silent Hill: Shattered Memories", "game"],
	[2012, 3, 13, "Silent Hill: Downpour", "game"], [2012, 10, 16, "Silent Hill: Book of Memories", "game"],
	[2014, 8, 12, "P.T.", "game"], [2024, 1, 31, "Silent Hill: The Short Message", "game"],
	[2024, 10, 8, "Silent Hill 2 (remake)", "game"], [2025, 9, 25, "Silent Hill f", "game"],
	[2026, 9, 24, "Silent Hill: Townfall", "game"],
	[2006, 4, 21, "Silent Hill (film)", "film"], [2012, 10, 26, "Silent Hill: Revelation (film)", "film"],
	[2026, 1, 23, "Return to Silent Hill (film)", "film"],
]

## Words that make a headline about a new entry in the series.
const NEW_ENTRY := ["announce", "reveal", "release date", "release window", "releases", "launch", "remake", "new silent hill",
	"next silent hill", "trailer", "teaser", "coming to", "waves", "in development", "leak", "first look", "pre-order",
	"preorder", "dlc", "expansion", "rated", "rating", "new game", "sequel", "port", "pc version", "steam"]
## Words that tie a headline to the series itself (not just a comparison).
const SERIES := ["konami", "townfall", "silent hill f", "silent hill 2", "silent hill 1", "silent hill: ", "silent hill remake",
	"silent hill origins", "silent hill 3", "silent hill 4", "homecoming", "downpour", "shattered memories", "book of memories",
	"short message", "p.t.", "pyramid head", "bloober", "neobards", "no code", "akira yamaoka", "masahiro ito", "silent hills",
	"silent hill game", "silent hill series", "silent hill franchise", "silent hill transmission", "silent hill ascension"]
## Headlines that only borrow the name ("a scene from 'Silent Hill'").
const OFF_TOPIC := ["scene from", "like silent hill", "-esque", "inspired by silent hill", "real-life silent hill",
	"real life silent hill", "turns into", "town that inspired"]

var items: Array = []        # [{title, source, url, at, new_entry, official}]
## Buy on PC: [{game, title, steam, stores: [{store, price, base, discount, url}], sale, best, key}],
## games on sale first. `sales` is the same list's on-sale part.
var shop: Array = []
var sales: Array = []
var pages: Array = []        # new store pages: [{key, store, title, url, kind, price, date, first}]
var checked := 0             # unix time of the last refresh
var busy := false
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = REFRESH
	_timer.autostart = true
	_timer.timeout.connect(func(): refresh(true))
	add_child(_timer)


func _seen() -> Dictionary:
	return App.settings.get("news_seen", {"sales": [], "items": [], "opened": 0})


func unseen() -> int:
	var seen := _seen()
	var n := 0
	for o in sales:
		if not seen.sales.has(o.key):
			n += 1
	for pg in pages:
		if not seen.get("pages", []).has(pg.key):
			n += 1
	for it in items:
		if it.new_entry and int(it.at) > int(seen.get("opened", 0)) and not seen.items.has(it.url):
			n += 1
	return n


## The News tab was opened: everything shown counts as seen.
func mark_seen() -> void:
	var seen := _seen()
	seen.sales = sales.map(func(o): return o.key)
	seen.pages = pages.map(func(pg): return pg.key)
	seen.items = items.filter(func(i): return i.new_entry).map(func(i): return i.url).slice(0, 80)
	seen.opened = int(Time.get_unix_time_from_system())
	App.set_setting("news_seen", seen)
	unseen_changed.emit(0)


## Fetches headlines, Steam announcements, store prices and store pages. With
## `alert`, new sales, new store pages and new-entry headlines get a notice.
func refresh(alert: bool = false, force: bool = false) -> void:
	if busy:
		return
	busy = true
	var left := [7]
	var heads := []
	var steam := []
	var got := {"steam": {}, "gog": [], "epic": {}, "search": [], "art": {}}
	var done := func():
		left[0] -= 1
		if left[0] > 0:
			return
		var before_sales := sales.map(func(o): return o.key)
		var before_pages := pages.map(func(pg): return pg.key)
		var before_items := items.filter(func(i): return i.new_entry).map(func(i): return i.url)
		items = _merge(heads, steam)
		shop = build_shop(got.steam, got.gog, got.epic, got.art)
		sales = shop.filter(func(o): return o.sale)
		pages = _new_pages(got.search, got.gog)
		checked = int(Time.get_unix_time_from_system())
		busy = false
		if alert:
			_alert(before_sales, before_pages, before_items)
		updated.emit()
		unseen_changed.emit(unseen())
	var ttl := 0 if force else TTL
	Net.get_text(NEWS_URL, ttl, func(xml: String):
		heads.append_array(parse_rss(xml))
		done.call())
	_steam_news(ttl, func(list: Array):
		steam.append_array(list)
		done.call())
	var ids := SHOP.filter(func(x): return x.has("steam")).map(func(x): return x.steam)
	Net.get_json(STEAM_PRICES % ",".join(ids), PackedStringArray(), ttl, func(d):
		if d is Dictionary:
			got.steam = d
		done.call())
	Net.get_json(GOG_CATALOG, PackedStringArray(), ttl, func(d):
		if d is Dictionary:
			got.gog = d.get("products", [])
		done.call())
	var eids := SHOP.filter(func(x): return x.has("epic")).map(func(x): return x.epic)
	Net.get_json(EPIC_PRICES % ",".join(eids), PackedStringArray(), ttl, func(d):
		if d is Dictionary:
			got.epic = d
		done.call())
	# Each Steam game's store capsule (newer games keep theirs at a hashed address).
	var arts := [ids.size()]
	for sid in ids:
		Net.get_json(STEAM_DETAILS % sid, PackedStringArray(), 7 * 86400, func(d):
			if d is Dictionary and d.get(sid, {}) is Dictionary:
				var data = d.get(sid, {}).get("data", {})
				if data is Dictionary:
					got.art[sid] = str(data.get("capsule_image", data.get("header_image", "")))
			arts[0] -= 1
			if arts[0] == 0:
				done.call())
	Net.get_json(STEAM_SEARCH, PackedStringArray(), ttl, func(d):
		if d is Dictionary:
			got.search = d.get("items", [])
		done.call())


func _steam_news(ttl: int, cb: Callable) -> void:
	var ids := []
	for g in App.games:
		var appid := str(g.get("install", {}).get("steam_appid", ""))
		if appid != "" and g.get("route", {}).get("kind", "") == "steam":
			ids.append([appid, str(g.title)])
	if ids.is_empty():
		cb.call([])
		return
	var out := []
	var left := [ids.size()]
	for pair in ids:
		Net.get_json(STEAM_NEWS % pair[0], PackedStringArray(), ttl, func(d):
			out.append_array(parse_steam_news(d, pair[1]))
			left[0] -= 1
			if left[0] == 0:
				cb.call(out))


func _alert(before_sales: Array, before_pages: Array, before_items: Array) -> void:
	var seen := _seen()
	var fresh_sales := sales.filter(func(o): return not before_sales.has(o.key) and not seen.sales.has(o.key))
	for o in fresh_sales.slice(0, 3):
		App.notify("On sale: %s, %d%% off on %s (%s)." % [o.title, int(o.best.discount), o.best.store, money(o.best.price)], "ok")
	if fresh_sales.size() > 3:
		App.notify("%d more Silent Hill games are on sale. See News." % (fresh_sales.size() - 3), "ok")
	for pg in pages.filter(func(x): return not before_pages.has(x.key) and not seen.get("pages", []).has(x.key)).slice(0, 2):
		App.notify("New on %s: %s" % [pg.store, pg.title])
	var fresh := items.filter(func(i): return i.new_entry and not before_items.has(i.url) and not seen.items.has(i.url) \
		and int(i.at) > int(seen.get("opened", 0)))
	if fresh.size() == 1:
		App.notify("Silent Hill news: " + str(fresh[0].title))
	elif fresh.size() > 1:
		App.notify("%d new Silent Hill headlines about new entries. See News." % fresh.size())


static func money(v: float) -> String:
	return "$%.2f" % v


# ------------------------------------------------------------------ parsing
## Google News RSS: [{title, source, url, at, new_entry, official}], kept to
## the series.
static func parse_rss(xml: String) -> Array:
	var out := []
	if xml.strip_edges() == "" or not xml.contains("<rss"):
		return out
	var p := XMLParser.new()
	if p.open_buffer(xml.to_utf8_buffer()) != OK:
		return out
	var cur := {}
	var field := ""
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				if n == "item":
					cur = {"title": "", "source": "", "url": "", "date": ""}
				elif not cur.is_empty() and n in ["title", "link", "pubDate", "source"]:
					field = n
				else:
					field = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not cur.is_empty() and field != "":
					var t := p.get_node_data()
					match field:
						"title": cur.title += t
						"link": cur.url += t.strip_edges()
						"pubDate": cur.date += t
						"source": cur.source += t
			XMLParser.NODE_ELEMENT_END:
				if p.get_node_name() == "item" and not cur.is_empty():
					var it := _headline(cur)
					if not it.is_empty():
						out.append(it)
					cur = {}
				field = ""
	return out


static func _headline(raw: Dictionary) -> Dictionary:
	var title: String = str(raw.title).strip_edges()
	var source: String = str(raw.source).strip_edges()
	# Google News adds " - <source>" to every title.
	if source != "" and title.ends_with(" - " + source):
		title = title.substr(0, title.length() - source.length() - 3)
	var low := title.to_lower()
	if not low.contains("silent hill") and not low.contains("townfall") and not low.contains("p.t."):
		return {}
	for w in OFF_TOPIC:
		if low.contains(w):
			return {}
	var series := false
	for w in SERIES:
		if low.contains(w):
			series = true
			break
	var new_entry := false
	for w in NEW_ENTRY:
		if low.contains(w):
			new_entry = true
			break
	var official := source.to_lower().contains("konami")
	if not (series or new_entry or official):
		return {}
	return {"title": title, "source": source, "url": str(raw.url), "at": rfc822(str(raw.date)),
		"new_entry": new_entry, "official": official}


## Steam announcements: [{title, source, url, at, new_entry, official}].
static func parse_steam_news(d, game: String) -> Array:
	var out := []
	if not d is Dictionary:
		return out
	for n in d.get("appnews", {}).get("newsitems", []):
		var title := str(n.get("title", "")).strip_edges()
		if title == "":
			continue
		var low := title.to_lower()
		var new_entry := false
		for w in NEW_ENTRY:
			if low.contains(w):
				new_entry = true
				break
		out.append({"title": title, "source": "Steam · " + game, "url": str(n.get("url", "")), "at": int(n.get("date", 0)),
			"new_entry": new_entry, "official": true})
	return out


## "Thu, 29 Oct 2026 18:00:23 GMT" -> unix time.
static func rfc822(s: String) -> int:
	var m := RegEx.create_from_string("(\\d{1,2}) (\\w{3}) (\\d{4}) (\\d{2}):(\\d{2}):(\\d{2})").search(s)
	if m == null:
		return 0
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return int(Time.get_unix_time_from_datetime_dict({"year": m.get_string(3).to_int(), "month": months.find(m.get_string(2)) + 1,
		"day": m.get_string(1).to_int(), "hour": m.get_string(4).to_int(), "minute": m.get_string(5).to_int(),
		"second": m.get_string(6).to_int()}))


## Headlines newest first, the same story from two places once.
func _merge(heads: Array, steam: Array) -> Array:
	var all := heads + steam
	all.sort_custom(func(a, b): return int(a.at) > int(b.at))
	var seen := {}
	var out := []
	for it in all:
		var k := RegEx.create_from_string("[^a-z0-9]").sub(str(it.title).to_lower(), "", true).left(48)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(it)
	return out.slice(0, 60)


## The official stores' prices per game: on sale first (biggest discount
## first), then the rest in release order (newest first).
func build_shop(steam: Dictionary, gog: Array, epic: Dictionary, art: Dictionary = {}) -> Array:
	var gog_by := {}
	for p in gog:
		gog_by[str(p.get("slug", ""))] = p
	var out := []
	for x in SHOP:
		var stores := []
		if x.has("steam"):
			var po: Dictionary = steam.get(x.steam, {}).get("data", {}).get("price_overview", {}) if steam.get(x.steam, {}) is Dictionary else {}
			if not po.is_empty():
				stores.append({"store": "Steam", "price": int(po.final) / 100.0, "base": int(po.initial) / 100.0,
					"discount": int(po.get("discount_percent", 0)), "url": STEAM_APP % x.steam})
		if x.has("gog") and gog_by.has(x.gog):
			var p: Dictionary = gog_by[x.gog]
			var pr: Dictionary = p.get("price", {})
			var fin := float(pr.get("finalMoney", {}).get("amount", "0"))
			var base := float(pr.get("baseMoney", {}).get("amount", "0"))
			if base > 0.0:
				stores.append({"store": "GOG", "price": fin, "base": base,
					"discount": int(round(100.0 * (1.0 - fin / base))) if fin < base else 0, "url": str(p.get("storeLink", ""))})
		if x.has("epic") and epic.get(x.epic, {}) is Dictionary:
			for d in epic.get(x.epic, {}).get("deals", []):
				if str(d.get("storeID", "")) == "25":
					var fin := float(d.get("price", 0))
					var base := float(d.get("retailPrice", 0))
					stores.append({"store": "Epic Games Store", "price": fin, "base": base,
						"discount": int(round(100.0 * (1.0 - fin / base))) if base > 0.0 and fin < base else 0,
						"url": EPIC_SEARCH % str(x.epic_q).uri_encode()})
		if stores.is_empty():
			continue
		stores.sort_custom(func(a, b): return a.price < b.price)
		var on := stores.filter(func(st): return st.discount > 0)
		var best: Dictionary = on[0] if not on.is_empty() else stores[0]
		var e := App.entry(x.game)
		# Wide art: Steam's store capsule, else GOG's store banner.
		var pic := str(art.get(str(x.get("steam", "")), ""))
		if pic == "" and x.has("gog") and gog_by.has(x.gog):
			pic = str(gog_by[x.gog].get("coverHorizontal", ""))
		out.append({"game": x.game, "art": pic, "title": str(e.get("title", x.game)) + ((" (%s)" % e.subtitle) if str(e.get("subtitle", "")) != "" else ""),
			"steam": str(x.get("steam", "")), "stores": stores, "sale": not on.is_empty(), "best": best,
			"year": int(e.get("year", 0)), "key": "%s@%s@%.2f" % [x.game, best.store, best.price]})
	var sale := out.filter(func(o): return o.sale)
	sale.sort_custom(func(a, b): return a.best.discount > b.best.discount)
	var rest := out.filter(func(o): return not o.sale)
	rest.sort_custom(func(a, b): return a.year > b.year)
	return sale + rest


## Silent Hill store pages that appeared since the launcher first looked:
## new games, editions, DLC. The first check only takes note of what's there.
func _new_pages(search: Array, gog: Array) -> Array:
	var known: Dictionary = App.settings.get("news_store_pages", {})
	var first_run := known.is_empty()
	var now := int(Time.get_unix_time_from_system())
	var found := []
	for it in search:
		var t := str(it.get("name", ""))
		if t.to_lower().contains("silent hill"):
			var pr = it.get("price", null)
			found.append({"key": "steam:%s" % str(it.get("id", "")), "store": "Steam", "title": t, "url": STEAM_APP % str(it.get("id", "")),
				"price": (int(pr.final) / 100.0) if pr is Dictionary else -1.0, "img": str(it.get("tiny_image", ""))})
	for p in gog:
		var t := str(p.get("title", ""))
		if t.to_lower().contains("silent hill"):
			found.append({"key": "gog:" + str(p.get("slug", "")), "store": "GOG", "title": t, "url": str(p.get("storeLink", "")),
				"price": float(p.get("price", {}).get("finalMoney", {}).get("amount", "-1")), "date": str(p.get("releaseDate", "")),
				"img": str(p.get("coverHorizontal", ""))})
	var out := []
	for f in found:
		if not known.has(f.key):
			known[f.key] = 0 if first_run else now
		f.first = int(known[f.key])
		if f.first > 0 and now - f.first < 60 * 86400:
			out.append(f)
	if not found.is_empty():
		App.set_setting("news_store_pages", known)
	out.sort_custom(func(a, b): return a.first > b.first)
	return out


## Release anniversaries from `days_before` days ago to `days_after` days ahead:
## [{title, kind, year, date (unix), years, days (0 today, <0 past, >0 coming)}].
static func history(days_before: int = 7, days_after: int = 7, now: int = 0) -> Array:
	if now == 0:
		now = int(Time.get_unix_time_from_system())
	var today := Time.get_datetime_dict_from_unix_time(now)
	var out := []
	for h in HISTORY:
		for yr in [int(today.year) - 1, int(today.year), int(today.year) + 1]:
			var t := int(Time.get_unix_time_from_datetime_dict({"year": yr, "month": h[1], "day": h[2], "hour": 12}))
			var t0 := int(Time.get_unix_time_from_datetime_dict({"year": today.year, "month": today.month, "day": today.day, "hour": 12}))
			var days := int(round((t - t0) / 86400.0))
			if days >= -days_before and days <= days_after and yr > int(h[0]):
				out.append({"title": h[3], "kind": h[4], "year": h[0], "date": t, "years": yr - int(h[0]), "days": days})
	out.sort_custom(func(a, b): return a.days < b.days)
	return out
