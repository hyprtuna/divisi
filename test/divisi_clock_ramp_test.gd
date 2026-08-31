extends GdUnitTestSuite

## A tempo ramp: [member DivisiClock.bpm] written on consecutive frames with a different value
## each time, which is the obvious reason to write it every frame at all.
##
## Kept apart from [code]divisi_clock_tempo_test.gd[/code], which covers a single write, both
## because gdUnit4 abandons a suite file at its first failure and because these two pull the
## beat grid's anchor in opposite directions: a single write wants the next beat a whole new
## beat away, and a ramp wants it not to be pushed away again on the next frame.
##
## Driven by hand at 60 frames per second, with no audio device.

var _clock: DivisiClock
var _beats: Array[int] = []


func before_test() -> void:
	_clock = auto_free(DivisiClock.new())
	_beats.clear()
	_clock.beat.connect(func(index: int) -> void: _beats.append(index))
	_clock.bpm = 120.0
	_clock.beats_per_bar = 4


func _run_frames(from_frame: int, to_frame: int) -> void:
	for i in range(from_frame, to_frame + 1):
		_clock.advance_to(float(i) / 60.0)


# Nudges the tempo by [param step] BPM on each of 240 frames, four seconds of ramp, advancing
# the clock after each write the way a game writing bpm in _process would.
func _ramp(from_frame: int, start_tempo: float, step: float) -> void:
	var tempo := start_tempo
	for i in range(from_frame, from_frame + 240):
		tempo += step
		_clock.bpm = tempo
		_clock.advance_to(float(i) / 60.0)


# Whether the beats came out one at a time, in order, starting from the beat after the last one
# the warm up emitted.
func _are_consecutive_from(first: int) -> bool:
	for i in _beats.size():
		if _beats[i] != first + i:
			return false
	return true


func test_a_tempo_ramped_up_over_four_seconds_still_emits_its_beats() -> void:
	# Re-anchoring the grid on the position of the write is right for a single write, and wrong
	# on every frame after the first of a ramp: it pushed the next beat one whole new tempo
	# beat past each write, and the next write pushed it again. A four second ramp from 120 to
	# 240 BPM emitted no beats at all, and skipped_beats read 0 while eight were owed.
	#
	# The ramp runs from just over 120 to 240 BPM, so it averages a little over 180, and four
	# seconds at 180 BPM is twelve beats.
	_clock.start()
	_run_frames(1, 120)
	assert_int(_clock.beat_index).is_equal(4)
	_beats.clear()

	_ramp(121, 120.0, 0.5)

	assert_float(_clock.bpm).is_equal_approx(240.0, 0.000001)
	assert_int(_beats.size()).is_between(10, 14)
	assert_bool(_are_consecutive_from(5)).is_true()
	assert_int(_clock.skipped_beats).is_equal(0)


func test_a_tempo_ramped_down_over_four_seconds_still_emits_its_beats() -> void:
	# The same the other way. A ramp down never blacked out, because each write moved the next
	# beat further away in a grid that was already slowing, but it lost beats to the same
	# arithmetic. Four seconds from just under 240 down to 120 BPM averages a little under 180
	# again, so it is twelve beats again.
	_clock.bpm = 240.0
	_clock.start()
	_run_frames(1, 120)
	assert_int(_clock.beat_index).is_equal(8)
	_beats.clear()

	_ramp(121, 240.0, -0.5)

	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)
	assert_int(_beats.size()).is_between(10, 14)
	assert_bool(_are_consecutive_from(9)).is_true()
	assert_int(_clock.skipped_beats).is_equal(0)


func test_a_ramp_does_not_fire_a_burst_when_it_ends() -> void:
	# The beat the ramp leaves owed has to be one beat, not the whole ramp arriving at once.
	# The two seconds after a ramp to 240 BPM hold exactly the eight beats 240 BPM has in them.
	_clock.start()
	_run_frames(1, 120)
	_ramp(121, 120.0, 0.5)
	var after_ramp := _clock.beat_index
	_beats.clear()

	_run_frames(361, 480)

	assert_int(_beats.size()).is_between(7, 9)
	assert_bool(_are_consecutive_from(after_ramp + 1)).is_true()
	assert_int(_clock.skipped_beats).is_equal(0)
