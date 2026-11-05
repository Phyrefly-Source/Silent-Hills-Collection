extends RefCounted
## Web image search for the art picker, through DuckDuckGo's image search (no
## account or key). It is an unofficial use of their site, so it can stop
## working; the picker then offers to search in your browser and paste a link.

const UA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"


## cb(results, error). results: [{url, thumb, width, height, title, source}]
## shape: "wide" (backgrounds), "logo" (transparent pictures) or "".
func search(query: String, shape: String, cb: Callable) -> void:
	var q := query.strip_edges()
	if q == "":
		cb.call([], "Type something to search for.")
		return
	var headers := PackedStringArray(["User-Agent: " + UA, "Accept-Language: en-US,en;q=0.9"])
	Net.get_text("https://duckduckgo.com/?q=%s&iax=images&ia=images" % q.uri_encode(), 3600, func(html: String):
		var m := RegEx.create_from_string("vqd=['\"]?([0-9a-zA-Z_-]+)").search(html)
		if m == null:
			cb.call([], "The search engine didn't answer.")
			return
		var f := ",,,,,,"
		if shape == "wide":
			f = "size:Wallpaper,,layout:Wide,,,,"
		elif shape == "logo":
			f = ",,,type:transparent,,,"
		var url := "https://duckduckgo.com/i.js?l=us-en&o=json&p=1&q=%s&vqd=%s&f=%s" % [q.uri_encode(), m.get_string(1), f.uri_encode()]
		var h2 := PackedStringArray(["User-Agent: " + UA, "Referer: https://duckduckgo.com/", "Accept: application/json, text/javascript, */*; q=0.01", "X-Requested-With: XMLHttpRequest"])
		Net.get_json(url, h2, 3600, func(res):
			if not (res is Dictionary) or not (res.get("results", null) is Array):
				cb.call([], "The search engine didn't return any pictures.")
				return
			var out := []
			for r in res.results:
				var img := str(r.get("image", ""))
				if not img.begins_with("http"):
					continue
				var thumb := str(r.get("thumbnail", img))
				if thumb.begins_with("//"):
					thumb = "https:" + thumb
				out.append({"url": img, "thumb": thumb, "width": int(r.get("width", 0)), "height": int(r.get("height", 0)),
					"title": str(r.get("title", "")), "source": str(r.get("url", ""))})
			cb.call(out, "" if not out.is_empty() else "No pictures found.")), headers)


## A browser search for when the built-in one can't be used.
static func browser_url(query: String) -> String:
	return "https://duckduckgo.com/?q=%s&iax=images&ia=images" % query.uri_encode()
