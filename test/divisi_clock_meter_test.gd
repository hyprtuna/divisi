extends GdUnitTestSuite

## What a meter written mid play does to the bar the music is already in.
##
## [code]divisi_clock_tempo_test.gd[/code] covers a meter change keeping the next bar on a
## downbeat. This is the other half: what the beat of the bar reads as between the write and
## the next beat, when the new bar is shorter than the beat of the bar the music is on.

var _clock: DivisiClock
var _bars: Array[int] = []


func before_test() -> void:
	_clock = auto_free(DivisiClock.new())
	_bars.clear()
	_clock.bar.connect(func(index: int) -> void: _bars.append(index))
	_clock.bpm = 120.0
	_clock.beats_per_bar = 4


func _run_frames(from_frame: int, to_frame: int) -> void:
	for i in range(from_frame, to_frame + 1):
		_clock.advance_to(float(i) / 60.0)


# Four beats of 4/4, leaving the clock on beat 3 of the bar with one bar announced.
func _on_the_last_beat_of_a_bar_of_four() -> void:
	_clock.start()
	_run_frames(1, 90)
	assert_int(_clock.beat_index).is_equal(3)
	assert_int(_clock.beat_in_bar).is_equal(3)
	assert_int(_clock.bar_index).is_equal(0)
	_bars.clear()


func test_shrinking_the_meter_to_one_announces_the_bar_it_closes() -> void:
	# mini(3, 0) is 0, so the readout said the beat that had just sounded was beat 0 of the
	# bar, a downbeat, and no bar signal had gone out for it. The comment beside that line
	# promised the opposite. A bar of one has no position that is not a downbeat, so the beat
	# is a downbeat under the new meter and the bar the shrink closed is announced, the same
	# way rebase() announces the one it re-anchors on.
	_on_the_last_beat_of_a_bar_of_four()

	_clock.beats_per_bar = 1

	assert_int(_clock.beat_in_bar).is_equal(0)
	assert_int(_clock.bar_index).is_equal(1)
	assert_array(_bars).is_equal([1])


func test_shrinking_the_meter_to_a_bar_that_still_holds_the_beat_announces_nothing() -> void:
	# The other side of the same guard, and the case the shipped arithmetic already got right.
	# A bar of two can hold a beat that is not a downbeat, so the count moves to the last beat
	# of the new bar and the bar finishes at the next beat rather than at this one.
	_on_the_last_beat_of_a_bar_of_four()

	_clock.beats_per_bar = 2

	assert_int(_clock.beat_in_bar).is_equal(1)
	assert_int(_clock.bar_index).is_equal(0)
	assert_array(_bars).is_empty()

	# And the bar really does finish at the next beat.
	_run_frames(91, 120)
	assert_int(_clock.beat_in_bar).is_equal(0)
	assert_array(_bars).is_equal([1])


func test_a_tempo_written_mid_play_never_announces_a_bar() -> void:
	# The re-anchor is shared between the two setters, and only a shorter bar can close one.
	_on_the_last_beat_of_a_bar_of_four()

	_clock.bpm = 200.0

	assert_int(_clock.beat_in_bar).is_equal(3)
	assert_int(_clock.bar_index).is_equal(0)
	assert_array(_bars).is_empty()
