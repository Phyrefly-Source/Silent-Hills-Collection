extends SceneTree
## Regression: choosing a sound profile from the dropdown (a real popup click)
## must leave the launcher taking input. Run with xvfb and a SILENTHILLS_ROOT.
func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.open_settings()
	for i in 10: await process_frame
	var panel = main.modal_layer.get_child(-1)
	for pick in [3, 2, 1, 3]:
		var obs := []
		var find := func(n, self_ref):
			for c in n.get_children():
				if c is OptionButton and c.item_count >= 4 and c.get_item_text(0) == "Off":
					obs.append(c)
				self_ref.call(c, self_ref)
		find.call(panel, find)
		var ob: OptionButton = obs[0]
		# scroll it into view
		var sc = ob.get_parent()
		while sc and not sc is ScrollContainer: sc = sc.get_parent()
		if sc: sc.ensure_control_visible(ob)
		for i in 3: await process_frame
		var t := Time.get_ticks_msec()
		await click(ob.get_global_rect().get_center())
		for i in 5: await process_frame
		var pm: PopupMenu = ob.get_popup()
		print("popup visible ", pm.visible, " at ", pm.position, " size ", pm.size)
		# item rects: approximate by even split
		var h := pm.size.y / float(pm.item_count)
		await click(Vector2(pm.position) + Vector2(pm.size.x / 2.0, h * (pick + 0.5)))
		for i in 10: await process_frame
		print("pick ", pick, " -> ", root.get_node("App").settings.sound_profile, " ", Time.get_ticks_msec() - t, " ms; gui_disable_input ", root.gui_disable_input, " popup ", pm.visible if is_instance_valid(pm) else "freed")
	quit()
