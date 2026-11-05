extends SceneTree
## While a game runs the launcher sits in the tray, deaf and silent; when the
## game closes it comes back. Controllers never reach it. Run with xvfb and
## SILENTHILLS_ROOT set.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w := root.get_window()
	var runner = root.get_node("App").svc("runner")
	var pad := 0
	for a in InputMap.get_actions():
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				pad += 1
	print("controller bindings left: ", pad)
	runner.session_started.emit("sh2")
	await process_frame
	print("playing: window visible ", w.visible, ", tray ", main._tray != null and main._tray.visible, " (", main._tray.tooltip if main._tray else "", "), gui input off ", root.gui_disable_input, ", sounds muted ", root.get_node("Sfx").muted)
	runner.session_ended.emit("sh2", 120)
	for i in 5:
		await process_frame
	print("closed: window visible ", w.visible, ", tray ", main._tray.visible, ", gui input off ", root.gui_disable_input)
	quit()
