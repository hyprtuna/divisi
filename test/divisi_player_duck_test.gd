extends GdUnitTestSuite

## The stinger duck: how far down it takes the music, how it comes back, and what it does
## with a depth that is not a duck at all.
##
## Headless Godot runs the Dummy audio driver, which still advances a playback position, so a
## stinger really can be scheduled, fired and released here. These tests therefore wait on
## real seconds rather than on a mocked clock.

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


func _music() -> AudioStreamPlayer:
	return _player.get_node(^"DivisiMusicA") as AudioStreamPlayer


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
	var music := _music()
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
	var music := _music()
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -12.0, 0.25)
	await get_tree().create_timer(0.9).timeout
	assert_float(music.volume_db).is_less(_player.volume_db - 1.0)
	await get_tree().create_timer(3.0).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)


func test_a_duck_releases_while_the_music_stream_is_paused(timeout := 20000) -> void:
	# The hold was measured against musical time, which stops when the music does. Pausing the
	# stream held the music 18 dB down for the whole pause and only let it back up afterwards.
	# The stinger has its own player and keeps running through a paused music stream, so the
	# hold is counted in the same seconds the release ramp already uses.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -18.0, 0.25)
	await _player.stinger_started
	music.stream_paused = true
	await get_tree().create_timer(STINGER.get_length() + 1.0).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)
	music.stream_paused = false


func test_a_positive_duck_is_ignored_rather_than_raising_the_music(timeout := 20000) -> void:
	# minf(0.0, duck_db) swallowed it in silence, so asking for +12 dB did nothing at all and
	# said nothing about it. A duck only lowers the music; asking it to raise the music is a
	# mistake worth hearing about.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	var ask := func() -> void: _player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, 12.0)
	await (assert_error(ask).is_push_warning(
		(
			"divisi: play_stinger was given duck_db +12.000000, which would raise the "
			+ "music rather than duck it. Ignoring it."
		)
	))
	await _player.stinger_started
	await get_tree().create_timer(0.2).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)


func test_a_bottomless_duck_stops_at_the_silence_floor(timeout := 20000) -> void:
	# -1e9 dB went straight to volume_db. The layer gains stop at DivisiClock.SILENCE_DB, which
	# is where the engine's own inspector hint for a synchronized stream's volume stops, and a
	# duck is a level like any other.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -1e9, 0.25)
	await _player.stinger_started
	await get_tree().process_frame
	var floored := _player.volume_db + DivisiClock.SILENCE_DB
	assert_float(music.volume_db).is_equal_approx(floored, 0.01)
