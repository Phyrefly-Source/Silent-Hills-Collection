extends SceneTree
## Pictures freed while they're still loading on worker threads (the
## Achievements, Concept Art and picker screens do this all the time).
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var NetImage = load("res://ui/widgets/net_image.gd")
	var holder := Control.new()
	root.add_child(holder)
	for round in 10:
		for i in 20:
			var img = NetImage.new("", Vector2(64, 64))
			img.max_px = 300 + (round * 30 + i) % 7   # a new cache key each time, so every one decodes
			holder.add_child(img)
			img.load_source("/tmp/claude-0/big.jpg")
		await process_frame
		for c in holder.get_children():
			c.queue_free()
		await process_frame
	await create_timer(3.0).timeout
	print("STRESS OK")
	quit()
