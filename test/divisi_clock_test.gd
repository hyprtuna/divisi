extends GdUnitTestSuite

## What DivisiClock counts: which beat a playback position falls on, that time never runs
## backwards under device jitter, and that a loop wrap keeps the count running instead of
## restarting it.
##
## Every test drives DivisiClock.advance_to() by hand, with no audio device and no
## AudioStreamPlayer, because CI cannot hear anything. Audible behaviour is covered by the
## manual checklist in the notes instead.

var _clock: DivisiClock
var _beats: Array[int]
var _bars: Array[int]


func before_test() -> void:
	_clock = auto_free(DivisiClock.new())
	_beats = []
	_bars = []
	_clock.beat.connect(func(index: int) -> void: _beats.append(index))
	_clock.bar.connect(func(index: int) -> void: _bars.append(index))
	_clock.bpm = 120.0
	_clock.beats_per_bar = 4


# 120 BPM: one beat is 0.5 s, one bar is 2.0 s.


func test_start_puts_the_indexes_before_the_first_beat() -> void:
	_clock.start()
	assert_int(_clock.beat_index).is_equal(-1)
	assert_int(_clock.bar_index).is_equal(-1)
	assert_bool(_clock.running).is_true()
	assert_array(_beats).is_empty()


func test_the_first_tick_emits_beat_zero_and_bar_zero() -> void:
	_clock.start()
	_clock.advance_to(0.0)
	assert_array(_beats).is_equal([0])
	assert_array(_bars).is_equal([0])
	assert_int(_clock.beat_in_bar).is_equal(0)


func test_beats_land_on_the_tempo_grid() -> void:
	_clock.start()
	_clock.advance_to(0.0)
	_clock.advance_to(0.49)
	assert_array(_beats).is_equal([0])
	_clock.advance_to(0.5)
	assert_array(_beats).is_equal([0, 1])
	_clock.advance_to(0.99)
	assert_array(_beats).is_equal([0, 1])
	_clock.advance_to(1.0)
	assert_array(_beats).is_equal([0, 1, 2])


func test_a_bar_is_emitted_every_four_beats() -> void:
	_clock.start()
	for step in 9:
		_clock.advance_to(float(step) * 0.5)
	assert_array(_beats).is_equal([0, 1, 2, 3, 4, 5, 6, 7, 8])
	assert_array(_bars).is_equal([0, 1, 2])
	assert_int(_clock.beat_in_bar).is_equal(0)


func test_beat_in_bar_is_already_correct_when_beat_fires() -> void:
	var seen: Array[int] = []
	_clock.beat.connect(func(_index: int) -> void: seen.append(_clock.beat_in_bar))
	_clock.start()
	for step in 6:
		_clock.advance_to(float(step) * 0.5)
	assert_array(seen).is_equal([0, 1, 2, 3, 0, 1])


func test_a_frame_that_skips_a_beat_still_emits_it() -> void:
	# A frame long enough to cross two beats emits both, in order. A beat handler that spawns
	# a note or a footstep must not silently lose one to a slow frame.
	_clock.start()
	_clock.advance_to(0.0)
	_clock.advance_to(1.2)
	assert_array(_beats).is_equal([0, 1, 2])


func test_a_long_stall_gives_up_rather_than_firing_a_burst() -> void:
	# Past MAX_CATCH_UP_BEATS the missed beats are counted, not emitted. Replaying two hundred
	# beat handlers after a level load is worse than admitting the gap.
	_clock.start()
	_clock.advance_to(0.0)
	_clock.advance_to(60.0)
	assert_int(_clock.beat_index).is_equal(120)
	assert_array(_beats).is_equal([0, 120])
	assert_int(_clock.skipped_beats).is_equal(119)


func test_musical_time_never_runs_backwards() -> void:
	# get_time_since_last_mix() is an estimate that can overshoot, so two reads can disagree in
	# the wrong direction. Without the clamp a beat handler fires the same beat twice.
	_clock.start()
	_clock.advance_to(1.0)
	assert_float(_clock.position).is_equal_approx(1.0, 0.0001)
	_clock.advance_to(0.994)
	assert_float(_clock.position).is_equal_approx(1.0, 0.0001)
	assert_array(_beats).is_equal([0, 1, 2])


func test_a_loop_wrap_keeps_counting_instead_of_restarting() -> void:
	_clock.start(16.0)
	_clock.advance_to(15.9)
	_clock.advance_to(0.1)
	assert_float(_clock.position).is_equal_approx(16.1, 0.0001)
	assert_int(_clock.beat_index).is_equal(32)
	assert_int(_clock.bar_index).is_equal(8)


func test_two_loops_keep_counting() -> void:
	_clock.start(16.0)
	_clock.advance_to(15.9)
	_clock.advance_to(0.1)
	_clock.advance_to(15.9)
	_clock.advance_to(0.2)
	assert_float(_clock.position).is_equal_approx(32.2, 0.0001)


func test_a_small_backwards_step_is_jitter_and_not_a_wrap() -> void:
	_clock.start(16.0)
	_clock.advance_to(8.0)
	_clock.advance_to(7.99)
	assert_float(_clock.position).is_equal_approx(8.0, 0.0001)


func test_a_stream_that_does_not_loop_never_wraps() -> void:
	_clock.start(0.0)
	_clock.advance_to(15.9)
	_clock.advance_to(0.1)
	assert_float(_clock.position).is_equal_approx(15.9, 0.0001)


func test_stop_leaves_the_counts_alone() -> void:
	_clock.start()
	_clock.advance_to(2.0)
	_clock.stop()
	assert_bool(_clock.running).is_false()
	assert_int(_clock.beat_index).is_equal(4)
	_clock.advance_to(4.0)
	assert_int(_clock.beat_index).is_equal(4)


func test_beat_and_bar_seconds_follow_the_tempo() -> void:
	_clock.bpm = 140.0
	_clock.beats_per_bar = 3
	assert_float(_clock.beat_seconds).is_equal_approx(60.0 / 140.0, 0.000001)
	assert_float(_clock.bar_seconds).is_equal_approx(3.0 * 60.0 / 140.0, 0.000001)


func test_a_long_stall_carries_the_bar_count_with_it() -> void:
	# The catch up path used to advance beat_index but count bars only by emission, so one
	# stall left bar_index reading low for the rest of the run.
	_clock.start()
	_clock.advance_to(0.0)
	_clock.advance_to(60.0)
	assert_int(_clock.beat_index).is_equal(120)
	assert_int(_clock.bar_index).is_equal(30)
	assert_int(_clock.beat_in_bar).is_equal(0)


func test_a_rebase_after_an_overshoot_never_replays_a_beat() -> void:
	# A frame long enough to cross the boundary by more than one beat has already emitted the
	# beats past it. rebase used to pull beat_index back to the boundary, so the next tick
	# emitted them again, with a decreasing index, on every transition that fired after a
	# hitch.
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(2.6)
	var before := _beats.duplicate()
	# The transition was scheduled for the bar line at 2.0; the frame landed at 2.6.
	_clock.rebase(2.0, 0.6, 16.0, 120.0, 4)
	_clock.advance_to(0.7)
	_clock.advance_to(1.2)
	assert_int(_clock.beat_index).is_greater_equal(before[-1])
	for i in range(1, _beats.size()):
		assert_int(_beats[i]).is_greater(_beats[i - 1])


func test_a_rebase_after_an_overshoot_still_announces_the_downbeat() -> void:
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(2.6)
	var bars_before := _bars.size()
	_clock.rebase(2.0, 0.6, 16.0, 120.0, 4)
	assert_int(_bars.size()).is_equal(bars_before + 1)


func test_the_system_clock_offset_reads_zero_before_the_clock_starts() -> void:
	assert_float(_clock.system_clock_offset_seconds).is_equal_approx(0.0, 0.000001)
