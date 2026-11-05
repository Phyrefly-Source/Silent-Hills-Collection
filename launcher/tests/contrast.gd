extends SceneTree
## Checks the design tokens against WCAG 2.2 AA (no rounding): text 4.5:1 on
## every surface it can sit on, component borders and the focus ring 3:1, and
## the games' accents once made readable (Style.accent_text).
func _initialize() -> void:
	var surfaces := {"BG": Style.BG, "SURFACE": Style.SURFACE, "RAISED": Style.RAISED, "HOVER": Style.HOVER}
	var bad := 0
	var rows := [["INK", Style.INK, 4.5], ["INK_2", Style.INK_2, 4.5], ["INK_3", Style.INK_3, 4.5],
		["ACCENT_TEXT", Style.ACCENT_TEXT, 4.5], ["OK", Style.OK, 4.5], ["DANGER", Style.DANGER, 4.5],
		["BORDER", Style.BORDER, 3.0], ["FOCUS", Style.FOCUS, 3.0]]
	for r in rows:
		for s in surfaces:
			var c := Style.contrast(r[1], surfaces[s])
			if c < r[2]:
				print("FAIL %s on %s: %.2f < %.1f" % [r[0], s, c, r[2]])
				bad += 1
	var on_fill := Style.contrast(Style.INK, Style.ACCENT)
	if on_fill < 4.5:
		print("FAIL INK on ACCENT: %.2f" % on_fill); bad += 1
	if Style.contrast(Style.BG, Style.INK) < 4.5:
		print("FAIL BG on INK (Primary)"); bad += 1
	var games: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/games.json")).games
	var films: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/films.json")).films
	for g in games + films:
		var a := Style.accent_text(Style.color_hex(str(g.get("accent", ""))))
		for s in surfaces:
			if Style.contrast(a, surfaces[s]) < 4.5:
				print("FAIL accent of %s on %s: %.2f" % [g.id, s, Style.contrast(a, surfaces[s])]); bad += 1
		var f := Style.accent_fill(Style.color_hex(str(g.get("accent", ""))))
		if Style.contrast(Style.INK, f) < 4.5:
			print("FAIL INK on fill of %s: %.2f" % [g.id, Style.contrast(Style.INK, f)]); bad += 1
	print("contrast checks failed: ", bad)
	quit(1 if bad else 0)
