extends SceneTree
## Decodes a few seconds of real ADX / AIX music to WAV and indexes an AFS.
func _initialize() -> void:
	var up := "/mnt/user-data/uploads/"
	for p in [up + "Silent Hill 2/sh2e/sound/adx/hotel/bgm_007.adx", up + "Silent Hill 2/sh2e/sound/adx/hotel/bgm_112.aix"]:
		var t0 := Time.get_ticks_msec()
		var b := FileAccess.get_file_as_bytes(p)
		var decs := []
		if p.ends_with(".aix"):
			for l in SoundContainers.aix_layers(b):
				decs.append(AdxStream.from_bytes(l))
		else:
			decs.append(AdxStream.from_bytes(b))
		var t1 := Time.get_ticks_msec()
		print(p.get_file(), " layers=", decs.size(), " ok=", decs[0].ok, " rate=", decs[0].rate, " ch=", decs[0].channels, " seconds=", decs[0].seconds(), " segments=", decs[0].segments.size(), " parse ms=", t1 - t0)
		var n: int = decs[0].rate * 20
		var mix := PackedVector2Array()
		mix.resize(n)
		var t2 := Time.get_ticks_msec()
		for d in decs:
			var part: PackedVector2Array = d.read(n)
			for i in part.size():
				mix[i] += part[i] / sqrt(decs.size())
		var t3 := Time.get_ticks_msec()
		print("  decoded 20 s x ", decs.size(), " layers in ", t3 - t2, " ms")
		var pcm := PackedByteArray()
		pcm.resize(n * 4)
		var peak := 0.0
		for i in n:
			var v := mix[i].clamp(Vector2(-1, -1), Vector2(1, 1))
			peak = max(peak, abs(v.x), abs(v.y))
			pcm.encode_s16(i * 4, int(v.x * 32767))
			pcm.encode_s16(i * 4 + 2, int(v.y * 32767))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.stereo = true
		w.mix_rate = decs[0].rate
		w.data = pcm
		w.save_to_wav("/tmp/claude-0/" + p.get_file() + ".wav")
		print("  peak ", peak)
	var afs := up + "Silent Hill 3/data/sound/sd.afs"
	var t4 := Time.get_ticks_msec()
	var e := SoundContainers.afs_entries(afs)
	print("afs entries ", e.size(), " first ", e[0], " last ", e[-1].name, " ms ", Time.get_ticks_msec() - t4)
	# Native loaders available?
	print("mp3 loader: ", ClassDB.class_has_method("AudioStreamMP3", "load_from_file"), " wav loader: ", ClassDB.class_has_method("AudioStreamWAV", "load_from_file"), " ogg: ", ClassDB.class_has_method("AudioStreamOggVorbis", "load_from_file"))
	quit()
