extends RefCounted
## Serves silenthillmemories.net from a local folder for screenshots and tests
## (SILENTHILLS_NET_FIXTURES=<dir>): <dir>/sh3/info_en.htm, <dir>/sh3/arts/pics/x.jpg …

var dir := ""
var search_file := "steam_search.json"


func reply(url: String):
	# News: <dir>/news/rss.xml, deals.json, stores.json, steam_<appid>.json
	var news := {"https://news.google.com/rss/": "rss.xml", "https://store.steampowered.com/api/appdetails": "steam_prices.json",
		"https://catalog.gog.com/v1/catalog": "gog.json", "https://www.cheapshark.com/api/1.0/games": "epic.json",
		"https://store.steampowered.com/api/storesearch": search_file}
	for prefix in news:
		if url.begins_with(prefix):
			var f := dir.path_join("news").path_join(news[prefix])
			if not FileAccess.file_exists(f):
				return null
			var txt := FileAccess.get_file_as_string(f)
			return txt if f.ends_with(".xml") else JSON.parse_string(txt)
	if url.contains("ISteamNews/GetNewsForApp"):
		var id := url.split("appid=")[1].split("&")[0]
		var f := dir.path_join("news/steam_%s.json" % id)
		return JSON.parse_string(FileAccess.get_file_as_string(f)) if FileAccess.file_exists(f) else {}
	var site := "https://www.silenthillmemories.net/"
	if not url.begins_with(site):
		return null
	var p := dir.path_join(url.substr(site.length()).split("?")[0])
	if url.ends_with(".htm"):
		return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	return p if FileAccess.file_exists(p) else ""
