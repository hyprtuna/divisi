extends GdUnitTestSuite

## Crossfade continuity: what the levels do when a transition fires while an earlier one is
## still fading.
##
## Levels are read in linear amplitude rather than in decibels wherever a player can be at
## digital silence. A fade that starts from silence is an infinite decibel step and a
## perfectly ordinary thing to hear; a jump in amplitude on a player that was already running
## is the click these tests exist to catch.

const EXPLORE := preload("res://demo/sections/explore.tres")
const COMBAT := preload("res://demo/sections/combat.tres")

var _player: DivisiPlayer


func before_test() -> void:
	_player = auto_free(DivisiPlayer.new())
	_player.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	add_child(_player)


func after_test() -> void:
	_player.stop()


func _music_players() -> Array[AudioStreamPlayer]:
	return [
		_player.get_node(^"DivisiMusicA") as AudioStreamPlayer,
		_player.get_node(^"DivisiMusicB") as AudioStreamPlayer
	]


func _other_section() -> StringName:
	return &"combat" if _player.current_section == EXPLORE else &"explore"


func test_back_to_back_transitions_never_step_a_running_level(timeout := 20000) -> void:
	# A transition firing while a crossfade was still running used to snap both players to the
	# endpoints of the new fade, stepping the surviving section up and cutting the other to
	# silence in one frame: two clicks. The new fade now begins where its curves already hold
	# the levels the old one left, so nothing on a player that kept running moves faster than
	# the fade itself.
	#
	# A player is only compared with itself while it keeps the same stream. Loading the
	# incoming section into a player is where a section legitimately starts from silence.
	_player.transition_seconds = 1.0
	_player.play(&"explore")
	await get_tree().create_timer(0.4).timeout

	var music := _music_players()
	var was_running := [false, false]
	var was_stream: Array[AudioStream] = [null, null]
	var was_amp := [0.0, 0.0]
	var worst := 0.0

	for frame in 90:
		if frame >= 30 and frame <= 32:
			_player.transition_to(_other_section(), DivisiQuantize.NOW)
		await get_tree().process_frame
		for i in music.size():
			var p := music[i]
			var amp := db_to_linear(p.volume_db) if p.playing else 0.0
			var same_stream: bool = p.stream == was_stream[i]
			if p.playing and was_running[i] and same_stream:
				worst = maxf(worst, absf(amp - was_amp[i]))
			was_running[i] = p.playing
			was_stream[i] = p.stream
			was_amp[i] = amp

	# Three transitions in three consecutive frames. The shipped behaviour measures 0.0104;
	# reverting the carry puts it above 0.9, which is the whole fade in one frame.
	assert_float(worst).is_less(0.05)


func test_a_cut_in_the_middle_of_a_fade_does_not_step_either_level(timeout := 20000) -> void:
	# Halfway through an equal power fade both players sit at the same gain, so a cut taken
	# there has to leave both of them exactly where they are. The content is spliced on both
	# sides; the levels are not.
	#
	# One ordinary frame of the fade, measured on the frame before the cut, is the yardstick.
	# The cut cannot be asked for a step of exactly zero because the fade it is replacing is
	# still moving during the frame the cut fires in.
	_player.transition_seconds = 2.0
	_player.play(&"explore")
	await get_tree().create_timer(0.3).timeout
	_player.transition_to(&"combat", DivisiQuantize.NOW)
	await get_tree().create_timer(1.0).timeout

	var music := _music_players()
	var before := [music[0].volume_db, music[1].volume_db]
	await get_tree().process_frame
	var drift := maxf(absf(music[0].volume_db - before[0]), absf(music[1].volume_db - before[1]))

	before = [music[0].volume_db, music[1].volume_db]
	_player.transition_to(&"explore", DivisiQuantize.NOW)
	await get_tree().process_frame

	# Reverting the carry steps the surviving player by 3.01 dB and the other by 77 dB.
	assert_float(absf(music[0].volume_db - before[0])).is_less(drift + 0.25)
	assert_float(absf(music[1].volume_db - before[1])).is_less(drift + 0.25)
