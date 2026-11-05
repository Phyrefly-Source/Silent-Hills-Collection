extends SceneTree
## News: headlines filtered and marked; official store prices (sale or full);
## new store pages after the first look; history; alerts once. Run with
## SILENTHILLS_NET_FIXTURES=<dir> holding news/rss.xml, steam_prices.json,
## gog.json, epic.json, steam_search.json, steam_search2.json.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app = root.get_node("App")
	var f = load("res://tests/net_fixture.gd").new()
	f.dir = OS.get_environment("SILENTHILLS_NET_FIXTURES")
	root.get_node("Net").fixture = f.reply
	app.set_setting("news_seen", {"sales": [], "items": [], "opened": 0})
	app.set_setting("news_store_pages", {})
	var notes := []
	app.toast.connect(func(t, _k): notes.append(t))
	var news = app.svc("news")
	news.refresh(true)
	while news.busy:
		await process_frame
	print("headlines: ", news.items.size())
	print("buy on PC:")
	for o in news.shop:
		print("  %s%s" % [o.title, "  [SALE]" if o.sale else ""])
		for st in o.stores:
			print("     %-18s %s  base %s  -%d%%" % [st.store, news.money(st.price), news.money(st.base), st.discount])
	print("new pages (first look): ", news.pages.size())
	print("alerts: ", notes)
	news.mark_seen()
	notes.clear()
	f.search_file = "steam_search2.json"
	news.refresh(true, true)
	while news.busy:
		await process_frame
	print("new pages: ", news.pages.map(func(p): return p.title))
	print("alerts the second time: ", notes)
	print("history around 29 Oct 2026: ", news.history(3, 7, 1793275200).map(func(h): return "%s %d %d" % [h.title, h.years, h.days]))
	print("history around 20 Sep 2026: ", news.history(3, 7, 1789900000).map(func(h): return "%s %d %d" % [h.title, h.years, h.days]))
	quit()
