extends GdUnitTestSuite

## What [method DivisiClock.from_dict] accepts.
##
## A state dictionary is the one input divisi takes from outside itself: a game restoring a
## save writes whatever is on disk into it. SECURITY.md names that path as the one worth
## scrutinising, so every field is checked against what playing can actually produce, and a
## value outside that is refused or clamped rather than carried into the clock's arithmetic.

var _clock: DivisiClock


func before_test() -> void:
	_clock = auto_free(DivisiClock.new())
	_clock.bpm = 120.0
	_clock.beats_per_bar = 4


func test_a_restored_tempo_of_zero_is_refused() -> void:
	_clock.from_dict({"bpm": 0.0})
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)


func test_a_restored_meter_of_zero_is_refused() -> void:
	_clock.from_dict({"beats_per_bar": 0})
	assert_int(_clock.beats_per_bar).is_equal(4)


func test_a_restored_beat_index_before_the_first_beat_is_clamped() -> void:
	# -1 is where start() puts it: before beat 0 and nowhere else.
	_clock.from_dict({"beat_index": -500})
	assert_int(_clock.beat_index).is_equal(-1)


func test_a_restored_bar_index_before_the_first_bar_is_clamped() -> void:
	_clock.from_dict({"bar_index": -9})
	assert_int(_clock.bar_index).is_equal(-1)


func test_a_restored_beat_of_the_bar_past_the_end_of_the_bar_is_clamped() -> void:
	# beat_in_bar 99 in a bar of 4 is a state no amount of playing could reach, and every bar
	# line answered from it afterwards would be wrong.
	_clock.from_dict({"beats_per_bar": 4, "beat_in_bar": 99})
	assert_int(_clock.beat_in_bar).is_equal(3)


func test_a_restored_position_before_the_start_is_clamped() -> void:
	_clock.from_dict({"position": -12.0})
	assert_float(_clock.position).is_equal_approx(0.0, 0.000001)


func test_restored_skipped_beats_cannot_be_negative() -> void:
	_clock.from_dict({"skipped_beats": -4})
	assert_int(_clock.skipped_beats).is_equal(0)


func test_a_sane_state_restores_untouched_and_a_missing_field_keeps_what_is_there() -> void:
	# The sanitising must not cost a real save its values, and a dictionary written by an older
	# version, missing keys this one has, still restores what it does carry.
	_clock.from_dict(
		{
			"bpm": 90.0,
			"beats_per_bar": 3,
			"position": 12.5,
			"beat_index": 18,
			"bar_index": 6,
			"beat_in_bar": 0,
			"skipped_beats": 2
		}
	)
	assert_float(_clock.bpm).is_equal_approx(90.0, 0.000001)
	assert_int(_clock.beats_per_bar).is_equal(3)
	assert_float(_clock.position).is_equal_approx(12.5, 0.000001)
	assert_int(_clock.beat_index).is_equal(18)
	assert_int(_clock.bar_index).is_equal(6)
	assert_int(_clock.beat_in_bar).is_equal(0)
	assert_int(_clock.skipped_beats).is_equal(2)

	_clock.from_dict({"beat_index": 21})
	assert_int(_clock.beat_index).is_equal(21)
	assert_float(_clock.bpm).is_equal_approx(90.0, 0.000001)
