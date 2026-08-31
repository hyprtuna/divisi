extends GdUnitTestSuite

## Scheduling: transitions that land on a boundary, stingers, and the state that survives a
## scene change.
##
## Headless Godot runs the Dummy audio driver, which still advances a playback position, so a
## transition really can be scheduled, fired and faded here. Several of these tests therefore
## wait on real seconds rather than on a mocked clock.

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


func test_transition_to_schedules_rather_than_cutting() -> void:
	_player.play(&"explore")
	var announced: Array[Array] = []
	_player.transition_started.connect(
		func(f: StringName, t: StringName, at: int) -> void: announced.append([f, t, at])
	)
	assert_bool(_player.transition_to(&"combat", DivisiQuantize.NEXT_BAR)).is_true()
	assert_object(_player.pending_section).is_same(COMBAT)
	# Still the old section: it has not fired yet.
	assert_object(_player.current_section).is_same(EXPLORE)
	assert_int(announced.size()).is_equal(1)
	assert_str(String(announced[0][1])).is_equal("combat")


func test_transition_to_the_section_already_playing_is_refused() -> void:
	_player.play(&"explore")
	assert_bool(_player.transition_to(&"explore")).is_false()
	assert_object(_player.pending_section).is_null()


func test_transition_to_an_unknown_section_is_refused() -> void:
	_player.play(&"explore")
	assert_bool(_player.transition_to(&"nothing")).is_false()
	assert_object(_player.pending_section).is_null()


func test_transition_to_before_anything_plays_just_plays() -> void:
	assert_bool(_player.transition_to(&"combat")).is_true()
	assert_bool(_player.playing).is_true()
	assert_object(_player.current_section).is_same(COMBAT)


func test_a_scheduled_transition_fires_and_swaps_the_section(timeout := 8000) -> void:
	_player.play(&"explore")
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BEAT)
	await get_tree().create_timer(1.0).timeout
	assert_object(_player.current_section).is_same(COMBAT)
	assert_object(_player.pending_section).is_null()
	assert_bool(_player.clock.running).is_true()


func test_the_outgoing_section_is_stopped_once_the_fade_ends(timeout := 8000) -> void:
	# Two players run at once only for the length of the crossfade. Leaving the old one
	# running is a silent doubling of the mix that nobody notices until it is four sections
	# deep.
	_player.play(&"explore")
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BEAT)
	await get_tree().create_timer(1.5).timeout
	assert_int(_playing_count()).is_equal(1)


func test_the_clock_keeps_counting_across_a_transition(timeout := 8000) -> void:
	_player.play(&"explore")
	await get_tree().create_timer(0.6).timeout
	var before := _player.clock.beat_index
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BEAT)
	await get_tree().create_timer(1.0).timeout
	assert_int(_player.clock.beat_index).is_greater(before)


func test_a_stinger_needs_the_music_running() -> void:
	assert_bool(_player.play_stinger(STINGER)).is_false()


func test_a_stinger_with_no_stream_is_refused() -> void:
	_player.play(&"explore")
	assert_bool(_player.play_stinger(null)).is_false()


func test_a_stinger_fires_on_the_next_beat(timeout := 8000) -> void:
	_player.play(&"explore")
	var fired := [0]
	_player.stinger_started.connect(func() -> void: fired[0] += 1)
	assert_bool(_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -6.0)).is_true()
	await get_tree().create_timer(1.0).timeout
	assert_int(fired[0]).is_equal(1)


func test_state_round_trips_into_a_second_player(timeout := 8000) -> void:
	# What a scene change does: capture on the way out, restore on the way in, and keep
	# counting bars rather than starting the music again from the top.
	_player.play(&"explore")
	_player.intensity = 0.6
	await get_tree().create_timer(0.8).timeout
	var saved := _player.capture_state()
	assert_dict(saved).is_not_empty()

	var second: DivisiPlayer = auto_free(DivisiPlayer.new())
	second.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	add_child(second)
	assert_bool(second.restore_state(saved)).is_true()
	assert_object(second.current_section).is_same(EXPLORE)
	assert_float(second.intensity).is_equal_approx(0.6, 0.001)
	assert_int(second.clock.beat_index).is_equal(_player.clock.beat_index)
	assert_float(second.clock.position).is_equal_approx(_player.clock.position, 0.05)
	second.stop()


func test_restoring_a_section_this_player_does_not_have_is_refused() -> void:
	assert_bool(_player.restore_state({"section": "nothing"})).is_false()
	assert_bool(_player.restore_state({})).is_false()


func test_the_announced_landing_bar_is_the_bar_it_lands_in(timeout := 15000) -> void:
	# transition_started used to announce bar_index + 1 unconditionally, which is wrong before
	# the first beat has been emitted, wrong for a NOW transition taken on a downbeat, and
	# wrong whenever a stall crosses a bar line before the boundary. It is the only thing a
	# listener has to schedule against, so it has to be the bar the music is actually in.
	_player.play(&"explore")
	await get_tree().create_timer(0.4).timeout
	var announced := [-99]
	var landed := [-99]
	_player.transition_started.connect(
		func(_f: StringName, _t: StringName, at: int) -> void: announced[0] = at
	)
	_player.section_changed.connect(
		func(_n: StringName) -> void: landed[0] = _player.clock.bar_index
	)
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BAR)
	await get_tree().create_timer(2.6).timeout
	assert_int(announced[0]).is_not_equal(-99)
	assert_int(landed[0]).is_equal(announced[0])


func test_cancel_transition_leaves_the_section_alone(timeout := 10000) -> void:
	_player.play(&"explore")
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BAR)
	assert_bool(_player.cancel_transition()).is_true()
	assert_object(_player.pending_section).is_null()
	assert_bool(_player.cancel_transition()).is_false()
	await get_tree().create_timer(2.5).timeout
	assert_object(_player.current_section).is_same(EXPLORE)


func test_a_stinger_without_a_duck_does_not_strand_an_earlier_one(timeout := 20000) -> void:
	# The duck depth used to be written at schedule time and read by the release ramp, so a
	# second stinger scheduled with the default duck of 0 while the first was still releasing
	# set the release rate to zero. The music stayed 9.5 dB down for the rest of the run.
	#
	# Only a second call that lands inside that release reaches the bug: the release opens
	# when the stinger ends and closes one release_seconds later. So the wait is derived from
	# the stinger's own length rather than written as a literal that a longer or shorter
	# stinger would put outside the window, and the test asserts it really is inside the
	# release before making the call. A wait that drifts past the window passes against the
	# defect it is supposed to catch, which is worse than no test.
	var depth_db := -12.0
	var release := 0.25
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _player.get_node(^"DivisiMusicA") as AudioStreamPlayer
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, depth_db, release)
	await _player.stinger_started
	await get_tree().create_timer(STINGER.get_length() + release * 0.5).timeout

	# Below the base level, but no longer at the full depth: the release is under way.
	assert_float(music.volume_db).is_less(_player.volume_db)
	assert_float(music.volume_db).is_greater(_player.volume_db + depth_db)

	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT)
	await get_tree().create_timer(3.0).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)


func test_a_duck_recovers_on_its_own(timeout := 20000) -> void:
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _player.get_node(^"DivisiMusicA") as AudioStreamPlayer
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -12.0, 0.25)
	await get_tree().create_timer(0.9).timeout
	assert_float(music.volume_db).is_less(_player.volume_db - 1.0)
	await get_tree().create_timer(3.0).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)


func test_restoring_after_a_transition_keeps_the_stems_in_phase(timeout := 20000) -> void:
	# The phase used to be recomputed as position modulo the loop length, which is only the
	# real source position when the section started at musical position 0. After a transition
	# it did not, so the music came back a beat out of phase with the beat grid and every
	# callback afterwards landed on the wrong musical spot.
	_player.play(&"explore")
	_player.transition_to(&"combat", DivisiQuantize.NEXT_BEAT)
	await get_tree().create_timer(2.0).timeout
	var saved := _player.capture_state()
	var before_phase: float = saved["clock"]["source_position"]

	var second: DivisiPlayer = auto_free(DivisiPlayer.new())
	second.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	add_child(second)
	assert_bool(second.restore_state(saved)).is_true()
	assert_object(second.current_section).is_same(COMBAT)
	assert_float(second.clock.source_position).is_equal_approx(before_phase, 0.05)
	# The restored grid must still put the next bar line on a real downbeat: a whole number of
	# bars after the downbeat the clock is currently counting from.
	var clock := second.clock
	var boundary := clock.next_boundary(DivisiQuantize.NEXT_BAR)
	var current_downbeat := clock.beat_index - clock.beat_in_bar
	assert_int((clock.beat_at(boundary) - current_downbeat) % clock.beats_per_bar).is_equal(0)
	second.stop()
