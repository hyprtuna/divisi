extends GdUnitTestSuite

## The stinger duck against a clock the game can move, and against depths and lengths that are
## not numbers.
##
## [code]divisi_player_duck_test.gd[/code] covers the duck itself. These are kept apart because
## gdUnit4 abandons a suite file at its first failure, and because this one writes
## [member Engine.time_scale], which has to be put back whether the case passes or fails.
##
## Headless Godot runs the Dummy audio driver, which still advances a playback position, so a
## stinger really can be scheduled, fired and released here. These tests therefore wait on real
## seconds rather than on a mocked clock.

const EXPLORE := preload("res://demo/sections/explore.tres")
const STINGER := preload("res://demo/audio/stinger.ogg")

var _player: DivisiPlayer


func before_test() -> void:
	_player = auto_free(DivisiPlayer.new())
	_player.sections = [EXPLORE] as Array[DivisiSection]
	add_child(_player)


func after_test() -> void:
	# Put back before anything else: a case that fails part way through has still moved it, and
	# every case after it in the run would be measuring a different second.
	Engine.time_scale = 1.0
	_player.stop()


func _music() -> AudioStreamPlayer:
	return _player.get_node(^"DivisiMusicA") as AudioStreamPlayer


# Waits until the music is back at its own level, and answers with how many wall seconds that
# took. Gives up at [param give_up_seconds] so a duck that never releases fails the assertion
# rather than hanging the run.
func _wall_seconds_until_released(music: AudioStreamPlayer, give_up_seconds: float) -> float:
	var started := Time.get_ticks_msec()
	var wall := 0.0
	while music.volume_db < _player.volume_db - 0.01:
		await get_tree().process_frame
		wall = float(Time.get_ticks_msec() - started) / 1000.0
		if wall > give_up_seconds:
			break
	return wall


func test_a_duck_is_over_in_wall_seconds_when_the_engine_is_slowed_down(timeout := 40000) -> void:
	# The hold was counted in the delta _process is handed, which Engine.time_scale scales. The
	# stinger's own audio is not scaled, so at a tenth speed a 1.2 s stinger held an 18 dB duck
	# for about 13.9 wall seconds: the music sat 18 dB down for more than twelve seconds after
	# the stinger everyone could hear had finished. Slow motion is exactly when a game fires a
	# stinger, and the docstring said plain seconds.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	var release := 0.25

	Engine.time_scale = 0.1
	_player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -18.0, release)
	await _player.stinger_started
	assert_float(music.volume_db).is_less(_player.volume_db - 1.0)

	var wall: float = await _wall_seconds_until_released(music, 20.0)
	# The stinger, its release, and a second of slack for the frame the release lands on.
	assert_float(wall).is_less(STINGER.get_length() + release + 1.0)


func test_a_duck_still_ends_when_the_engine_is_stopped_dead(timeout := 40000) -> void:
	# Engine.time_scale = 0.0 is a pause a game implements itself rather than through the scene
	# tree, and it hands _process a delta of zero on every frame. A hold counted in frame time
	# never advances at all there: the music stayed 18 dB down for as long as anything was
	# willing to wait, which is the same never-ends failure a hold measured against a stopped
	# musical clock had. The wall clock does not stop when the engine's does.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	var release := 0.25

	Engine.time_scale = 0.0
	_player.play_stinger(STINGER, DivisiQuantize.NOW, -18.0, release)
	await _player.stinger_started
	assert_float(music.volume_db).is_less(_player.volume_db - 1.0)

	var wall: float = await _wall_seconds_until_released(music, 20.0)
	assert_float(wall).is_less(STINGER.get_length() + release + 1.0)


func test_a_release_that_is_not_a_number_is_refused(timeout := 20000) -> void:
	# maxf(0.0, NAN) is NAN, and _duck_release_seconds <= 0.0 is false for it, so the ramp's
	# own t was NAN, the depth was NAN, and is_zero_approx(NAN) is false: the duck never
	# cleared. The music stayed down for the rest of the run while the engine logged "Volume
	# can't be set to NaN" on every frame.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	var ask := func() -> void: _player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, -12.0, NAN)
	await (assert_error(ask).is_push_warning(
		(
			"divisi: play_stinger was given release_seconds nan, which is not a length of time. "
			+ "Using 0.250000."
		)
	))
	await _player.stinger_started
	var wall: float = await _wall_seconds_until_released(music, 10.0)
	assert_float(wall).is_less(STINGER.get_length() + 1.0)
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)


func test_a_duck_depth_that_is_not_a_number_is_ignored(timeout := 20000) -> void:
	# A duck of +12 dB is refused out loud, and a duck of NAN was refused in silence: clampf
	# answers NAN, the "is it negative" test that follows is false for NAN, and nothing ducked
	# and nothing was said. The same policy applies to both.
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	var music := _music()
	var ask := func() -> void: _player.play_stinger(STINGER, DivisiQuantize.NEXT_BEAT, NAN)
	await (assert_error(ask).is_push_warning(
		"divisi: play_stinger was given duck_db nan, which is not a level. Ignoring it."
	))
	await _player.stinger_started
	await get_tree().create_timer(0.2).timeout
	assert_float(music.volume_db).is_equal_approx(_player.volume_db, 0.01)
