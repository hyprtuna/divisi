extends GdUnitTestSuite

## What DivisiClock schedules against: where the next beat and bar boundaries are, what a
## section change does to the grid, the latency arithmetic, and the state that survives a
## scene change.
##
## Every test drives DivisiClock.advance_to() by hand, with no audio device and no
## AudioStreamPlayer.

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


func test_next_beat_boundary() -> void:
	_clock.start()
	_clock.advance_to(0.7)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BEAT)).is_equal_approx(1.0, 0.0001)
	assert_float(_clock.time_to_next(DivisiQuantize.NEXT_BEAT)).is_equal_approx(0.3, 0.0001)


func test_next_bar_boundary() -> void:
	_clock.start()
	_clock.advance_to(0.7)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(2.0, 0.0001)
	assert_float(_clock.time_to_next(DivisiQuantize.NEXT_BAR)).is_equal_approx(1.3, 0.0001)


func test_next_bar_from_late_in_the_bar() -> void:
	_clock.start()
	_clock.advance_to(1.9)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(2.0, 0.0001)


func test_next_bar_from_exactly_on_a_downbeat_is_the_bar_after() -> void:
	_clock.start()
	_clock.advance_to(2.0)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(4.0, 0.0001)


func test_now_is_now() -> void:
	_clock.start()
	_clock.advance_to(0.7)
	assert_float(_clock.next_boundary(DivisiQuantize.NOW)).is_equal_approx(0.7, 0.0001)
	assert_float(_clock.time_to_next(DivisiQuantize.NOW)).is_equal_approx(0.0, 0.0001)


func test_boundaries_follow_a_three_four_time_signature() -> void:
	_clock.beats_per_bar = 3
	_clock.start()
	_clock.advance_to(0.1)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(1.5, 0.0001)


func test_beat_at_reads_the_grid() -> void:
	_clock.start()
	assert_int(_clock.beat_at(0.0)).is_equal(0)
	assert_int(_clock.beat_at(0.75)).is_equal(1)
	assert_int(_clock.beat_at(2.0)).is_equal(4)


func test_a_bar_quantized_rebase_does_not_announce_the_downbeat_twice() -> void:
	# The clock ticks first and emits the downbeat at the boundary, then the player rebases on
	# to the incoming section. Announcing it again would fire every bar handler twice on every
	# transition.
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(2.01)
	assert_array(_bars).is_equal([0, 1])
	_clock.rebase(2.0, 0.01, 16.0, 120.0, 4)
	assert_array(_bars).is_equal([0, 1])
	assert_array(_beats).is_equal([0, 1, 2, 3, 4])
	assert_int(_clock.beat_index).is_equal(4)
	assert_int(_clock.beat_in_bar).is_equal(0)


func test_a_beat_quantized_rebase_re_anchors_the_bar_grid() -> void:
	# The incoming stems start at their own downbeat, so a transition taken on an offbeat moves
	# the bar line to land there.
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(0.51)
	assert_array(_bars).is_equal([0])
	assert_int(_clock.beat_in_bar).is_equal(1)
	_clock.rebase(0.5, 0.01, 16.0, 120.0, 4)
	assert_array(_bars).is_equal([0, 1])
	assert_int(_clock.beat_in_bar).is_equal(0)
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(2.5, 0.0001)


func test_rebase_keeps_the_beat_count_running_across_sections() -> void:
	_clock.start(16.0)
	for step in 5:
		_clock.advance_to(float(step) * 0.5)
	_clock.rebase(2.0, 0.0, 16.0, 120.0, 4)
	_clock.advance_to(0.5)
	assert_int(_clock.beat_index).is_equal(5)
	assert_float(_clock.position).is_equal_approx(2.5, 0.0001)


func test_rebase_changes_tempo_from_the_boundary_on() -> void:
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(2.0)
	_clock.rebase(2.0, 0.0, 12.0, 180.0, 3)
	assert_float(_clock.bpm).is_equal_approx(180.0, 0.0001)
	assert_int(_clock.beats_per_bar).is_equal(3)
	# One beat at 180 BPM is a third of a second.
	_clock.advance_to(0.34)
	assert_int(_clock.beat_index).is_equal(5)


func test_rebase_survives_a_loop_wrap_afterwards() -> void:
	_clock.start(16.0)
	_clock.advance_to(0.0)
	_clock.advance_to(2.0)
	_clock.rebase(2.0, 0.0, 16.0, 120.0, 4)
	_clock.advance_to(15.9)
	_clock.advance_to(0.1)
	assert_float(_clock.position).is_equal_approx(18.1, 0.0001)


func test_latency_compensation_arithmetic() -> void:
	# position + time since the last mix - output latency, which is what the engine's own
	# audio sync tutorial prescribes.
	assert_float(DivisiClock.compensate(1.0, 0.005, 0.020)).is_equal_approx(0.985, 0.000001)
	assert_float(DivisiClock.compensate(10.0, 0.0, 0.0)).is_equal_approx(10.0, 0.000001)


func test_a_stalled_audio_thread_cannot_push_the_clock_forward() -> void:
	# since_last_mix is bounded by the output latency before it is used. Without that, a frame
	# that stalls for 200 ms reports 200 ms of audio progress that did not happen, and the
	# monotonic clamp then keeps it forever.
	assert_float(DivisiClock.compensate(5.0, 0.200, 0.020)).is_equal_approx(5.0, 0.000001)
	assert_float(DivisiClock.compensate(5.0, 0.200, 0.0)).is_equal_approx(5.0, 0.000001)


func test_latency_compensation_never_returns_a_negative_time() -> void:
	# On the first frames of playback the latency term is larger than the position.
	assert_float(DivisiClock.compensate(0.001, 0.0, 0.050)).is_equal_approx(0.0, 0.000001)


func test_the_system_clock_offset_reads_zero_before_the_clock_starts() -> void:
	assert_float(_clock.system_clock_offset_seconds).is_equal_approx(0.0, 0.000001)


func test_state_round_trips_through_a_dictionary() -> void:
	_clock.start(16.0)
	for step in 7:
		_clock.advance_to(float(step) * 0.5)
	var saved := _clock.to_dict()

	var restored: DivisiClock = auto_free(DivisiClock.new())
	restored.from_dict(saved)
	assert_float(restored.position).is_equal_approx(_clock.position, 0.0001)
	assert_int(restored.beat_index).is_equal(_clock.beat_index)
	assert_int(restored.bar_index).is_equal(_clock.bar_index)
	assert_int(restored.beat_in_bar).is_equal(_clock.beat_in_bar)
	assert_float(restored.bpm).is_equal_approx(_clock.bpm, 0.0001)


func test_from_dict_keeps_what_an_older_save_does_not_carry() -> void:
	_clock.bpm = 90.0
	_clock.from_dict({"position": 4.0})
	assert_float(_clock.position).is_equal_approx(4.0, 0.0001)
	assert_float(_clock.bpm).is_equal_approx(90.0, 0.0001)


func test_resync_puts_a_restored_count_back_on_the_grid() -> void:
	# Restored into a new scene at bar 8 beat 2, with the stream dropped back in at the phase
	# that position sits at inside a 16 second loop.
	(
		_clock
		. from_dict(
			{
				"bpm": 120.0,
				"beats_per_bar": 4,
				"position": 17.0,
				"beat_index": 34,
				"bar_index": 8,
				"beat_in_bar": 2,
			}
		)
	)
	_clock.resync_source(fposmod(17.0, 16.0), 16.0)
	assert_float(_clock.position).is_equal_approx(17.0, 0.0001)
	assert_int(_clock.beat_index).is_equal(34)
	# The stream's own first sample is a downbeat, so the next bar line is two beats away.
	assert_float(_clock.next_boundary(DivisiQuantize.NEXT_BAR)).is_equal_approx(18.0, 0.0001)
	_clock.advance_to(1.5)
	assert_int(_clock.beat_index).is_equal(35)
	assert_float(_clock.position).is_equal_approx(17.5, 0.0001)
