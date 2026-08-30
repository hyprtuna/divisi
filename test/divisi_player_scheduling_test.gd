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
	assert_int(announced[0][2]).is_equal(_player.clock.bar_index + 1)


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
