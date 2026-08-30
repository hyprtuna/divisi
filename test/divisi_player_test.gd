extends GdUnitTestSuite

## Starting a section and driving its layers, against real playback.
##
## Headless Godot runs the Dummy audio driver, which still advances a playback position, so
## these tests play sound that nobody hears and then measure what divisi wrote. What they
## cannot check is whether the result sounds right; that is what the manual checklist is for.

const EXPLORE := preload("res://demo/sections/explore.tres")
const COMBAT := preload("res://demo/sections/combat.tres")
const STINGER := preload("res://demo/audio/stinger.ogg")

var _player: DivisiPlayer


func before_test() -> void:
	_player = auto_free(DivisiPlayer.new())
	_player.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	_player.transition_seconds = 0.2
	add_child(_player)


func after_test() -> void:
	_player.stop()


func _active_stream() -> AudioStreamSynchronized:
	for child in _player.get_children():
		if child is AudioStreamPlayer and child.playing:
			var sync := child.stream as AudioStreamSynchronized
			if sync != null:
				return sync
	return null


func _playing_count() -> int:
	var n := 0
	for child in _player.get_children():
		if child is AudioStreamPlayer and child.playing:
			n += 1
	return n


func test_find_section_looks_up_by_name() -> void:
	assert_object(_player.find_section(&"explore")).is_same(EXPLORE)
	assert_object(_player.find_section(&"combat")).is_same(COMBAT)
	assert_object(_player.find_section(&"nothing")).is_null()


func test_play_starts_the_named_section() -> void:
	assert_bool(_player.play(&"combat")).is_true()
	assert_bool(_player.playing).is_true()
	assert_object(_player.current_section).is_same(COMBAT)
	assert_bool(_player.clock.running).is_true()
	assert_float(_player.clock.bpm).is_equal_approx(COMBAT.bpm, 0.001)


func test_play_refuses_a_section_it_does_not_have() -> void:
	assert_bool(_player.play(&"nothing")).is_false()
	assert_bool(_player.playing).is_false()


func test_play_mixes_one_stream_per_layer() -> void:
	_player.play(&"explore")
	var sync := _active_stream()
	assert_object(sync).is_not_null()
	assert_int(sync.stream_count).is_equal(EXPLORE.mixed_layers().size())


func test_intensity_writes_layer_volumes_into_the_playing_stream() -> void:
	# The engine reads these on every mix chunk, so writing them is the whole of layering.
	_player.play(&"explore")
	_player.intensity = 0.0
	var sync := _active_stream()
	var quiet: Array[float] = []
	for i in sync.stream_count:
		quiet.append(sync.get_sync_stream_volume(i))
	_player.intensity = 1.0
	var loud: Array[float] = []
	for i in sync.stream_count:
		loud.append(sync.get_sync_stream_volume(i))
	assert_array(loud).is_not_equal(quiet)
	for i in EXPLORE.mixed_layers().size():
		assert_float(loud[i]).is_equal_approx(EXPLORE.mixed_layers()[i].gain_db(1.0), 0.001)


func test_layer_gains_reports_what_is_being_mixed() -> void:
	_player.play(&"explore")
	_player.intensity = 0.5
	var gains := _player.layer_gains()
	assert_int(gains.size()).is_equal(EXPLORE.mixed_layers().size())
	assert_str(String(gains[0]["name"])).is_not_empty()


func test_stop_puts_everything_down() -> void:
	_player.play(&"explore")
	_player.stop()
	assert_bool(_player.playing).is_false()
	assert_object(_player.current_section).is_null()
	assert_bool(_player.clock.running).is_false()
	assert_int(_playing_count()).is_equal(0)


func test_beats_stay_on_the_grid_over_a_long_run(timeout := 25000) -> void:
	# The property that separates this clock from one that accumulates delta: after seconds of
	# playback the beat count still matches the musical position, with nothing dropped and
	# nothing invented. A delta clock passes this at second one and fails it at minute ten,
	# so the manual checklist runs the same idea for ten minutes on real hardware.
	_player.play(&"explore")
	await get_tree().create_timer(8.0).timeout
	var clock := _player.clock
	var expected := floori(clock.position / clock.beat_seconds)
	assert_int(clock.beat_index).is_equal(expected)
	assert_int(clock.bar_index).is_equal(expected / clock.beats_per_bar)
	assert_int(clock.skipped_beats).is_equal(0)


func test_the_clock_follows_the_audio_device_and_not_the_frame_rate(timeout := 25000) -> void:
	# What the clock reports must be what the device reports, to within the resolution of a
	# frame, and must still match it after seconds of playback. This is the test a clock built
	# by accumulating delta cannot pass, and it is the contract divisi actually offers.
	#
	# What is deliberately NOT asserted here is the musical position against the wall clock.
	# Headless CI runs the dummy audio driver, whose mix scheduling is tied to the main loop,
	# so under a test runner its audio clock departs from wall time by an amount that measures
	# the runner rather than divisi. Measured standalone on this driver the departure is
	# bounded and does not trend, within about 56 ms over 8 seconds in both directions, but
	# that number is a property of the dummy driver. The wall clock claim needs real hardware
	# and is checked by hand against the demo's readout.
	_player.play(&"explore")
	await get_tree().create_timer(6.0).timeout
	var device := DivisiClock.compensated_position(_player.get_node(^"DivisiMusicA"))
	assert_float(absf(_player.clock.position - device)).is_less(0.05)


func test_a_stalled_frame_does_not_move_the_system_clock_offset(timeout := 20000) -> void:
	# system_clock_offset_seconds samples the musical position and the wall clock at the same
	# instant. It used to read a live wall clock against a position last written a frame ago,
	# so a hitch alone showed up in it: a 200 ms stall reported 166 ms. The demo puts this
	# number on screen to make a point about clocks, so a slow frame must not move it.
	_player.play(&"explore")
	await get_tree().create_timer(1.0).timeout
	var before := _player.clock.system_clock_offset_seconds
	var until := Time.get_ticks_usec() + 200000
	while Time.get_ticks_usec() < until:
		pass
	assert_float(_player.clock.system_clock_offset_seconds).is_equal_approx(before, 0.001)


func _one_shot_section() -> DivisiSection:
	# A section whose stem does not loop. The stinger is the only non-looping stream in the
	# demo, which is exactly the mistake this guards: a stem imported with Loop unticked.
	var layer := DivisiLayer.new()
	layer.layer_name = &"oneshot"
	layer.stream = STINGER
	var section := DivisiSection.new()
	section.section_name = &"oneshot"
	section.bpm = 120.0
	section.beats_per_bar = 4
	section.layers = [layer] as Array[DivisiLayer]
	return section


func test_a_section_whose_stems_do_not_loop_reports_no_loop_length() -> void:
	# Telling the clock a length for a stream that will not wrap makes it wait forever for a
	# wrap that never comes.
	var section := _one_shot_section()
	assert_float(section.loop_length()).is_equal_approx(0.0, 0.0001)
	assert_bool(section.loops()).is_false()
	assert_bool(EXPLORE.loops()).is_true()


func test_a_section_that_runs_out_stops_instead_of_freezing(timeout := 15000) -> void:
	# Without this the player sat with playing still true, the clock frozen at the last
	# position it read, and any scheduled transition waiting on a boundary that could never
	# arrive. A silent hang is the worst way to tell somebody they forgot to tick Loop.
	var section := _one_shot_section()
	_player.sections = [section] as Array[DivisiSection]
	var finished: Array[StringName] = []
	_player.playback_finished.connect(func(n: StringName) -> void: finished.append(n))
	assert_bool(_player.play(&"oneshot")).is_true()
	await get_tree().create_timer(2.5).timeout
	assert_bool(_player.playing).is_false()
	assert_array(finished).is_equal([&"oneshot"] as Array[StringName])


func test_a_section_with_no_usable_layer_is_refused() -> void:
	# It would build a synchronized stream with no sub streams, whose playback position stays
	# at zero, so play() would report success and musical time would never move.
	var empty := DivisiSection.new()
	empty.section_name = &"empty"
	_player.sections = [empty] as Array[DivisiSection]
	assert_bool(_player.play(&"empty")).is_false()
	assert_bool(_player.playing).is_false()


func test_play_before_the_player_is_in_the_tree_is_refused() -> void:
	var loose: DivisiPlayer = auto_free(DivisiPlayer.new())
	loose.sections = [EXPLORE] as Array[DivisiSection]
	assert_bool(loose.play(&"explore")).is_false()
