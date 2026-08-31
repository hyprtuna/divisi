extends GdUnitTestSuite

## The values the clock refuses, on the two surfaces a game can hand it one.
##
## [member DivisiClock.bpm] and [member DivisiClock.beats_per_bar] are written by code and by
## the inspector, and [method DivisiClock.from_dict] is handed whatever a save file holds.
## [code]divisi_clock_restore_test.gd[/code] covers the counts a save can carry; this suite
## covers the ones it cannot, which is the surface SECURITY.md names. They are kept apart
## because gdUnit4 abandons a suite file at its first failure, so a red case here would hide
## the cases that follow it.

var _clock: DivisiClock


func before_test() -> void:
	_clock = auto_free(DivisiClock.new())
	_clock.bpm = 120.0
	_clock.beats_per_bar = 4


func test_a_tempo_that_is_not_a_number_is_refused() -> void:
	# NAN passed the "greater than 0" guard, because every comparison against NAN is false.
	# beat_seconds became NAN with it, next_boundary() answered NAN, and a pending transition
	# could never fire because position >= NAN is false too: a clock that looks alive and never
	# emits again, which is the case the guard exists for.
	var write_nan := func() -> void: _clock.bpm = NAN
	await (assert_error(write_nan).is_push_error(
		"divisi: bpm must be a finite number. Refusing nan, the tempo stays 120.000000."
	))
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)
	assert_float(_clock.beat_seconds).is_equal_approx(0.5, 0.000001)


func test_an_infinite_tempo_is_refused() -> void:
	# bpm = 60.0 / interval with a zero interval is an ordinary way to reach INF, and it made
	# beat_seconds 0.0, which is a beat grid with no beats on it.
	var write_inf := func() -> void: _clock.bpm = INF
	await (assert_error(write_inf).is_push_error(
		"divisi: bpm must be a finite number. Refusing inf, the tempo stays 120.000000."
	))
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)
	assert_float(_clock.beat_seconds).is_equal_approx(0.5, 0.000001)


func test_a_meter_that_is_not_a_number_or_is_infinite_is_refused() -> void:
	# beats_per_bar is an int, so NAN and INF are converted before the setter sees them, and
	# both arrive as the smallest 64 bit integer. The guard that refuses zero and negative
	# already catches them; this holds that shut rather than reporting a hole that is not there.
	_clock.beats_per_bar = NAN
	assert_int(_clock.beats_per_bar).is_equal(4)
	_clock.beats_per_bar = INF
	assert_int(_clock.beats_per_bar).is_equal(4)


func test_a_meter_too_long_to_be_a_bar_is_refused() -> void:
	# The same argument the tempo makes at the other end. A bar of a million beats at 120 BPM
	# is 5787 days long: a meter that looks set and never produces a downbeat.
	var write_huge := func() -> void: _clock.beats_per_bar = 1000000
	await (assert_error(write_huge).is_push_error(
		"divisi: beats_per_bar must be at most 1024. Refusing 1000000, the meter stays 4."
	))
	assert_int(_clock.beats_per_bar).is_equal(4)


func test_a_restored_infinite_tempo_is_refused() -> void:
	var restore := func() -> void: _clock.from_dict({"bpm": INF})
	await (assert_error(restore).is_push_warning(
		"divisi: restored state has bpm inf, which is not a tempo. Keeping 120.000000."
	))
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)


func test_a_restored_infinite_position_is_refused() -> void:
	_clock.position = 3.5
	var restore := func() -> void: _clock.from_dict({"position": INF})
	await (assert_error(restore).is_push_warning(
		"divisi: restored state has position inf, which is not a number of seconds. Keeping it."
	))
	assert_float(_clock.position).is_equal_approx(3.5, 0.000001)


func test_a_restored_beat_index_past_any_run_is_clamped() -> void:
	# The largest 64 bit integer restored verbatim left the clock counting from a beat it could
	# never advance past, because the next beat overflows: it never emitted again.
	# The bar fields are given consistent values so that the beat count is the only thing this
	# has to say anything about.
	var saved := {"beat_index": 9223372036854775807, "bar_index": 250000000, "beat_in_bar": 0}
	var restore := func() -> void: _clock.from_dict(saved)
	await (assert_error(restore).is_push_warning(
		(
			"divisi: restored state has beat_index 9223372036854775807, past the 1000000000 "
			+ "that playing can reach. Clamping."
		)
	))
	assert_int(_clock.beat_index).is_equal(1000000000)


func test_a_restored_bar_count_no_beat_count_could_reach_is_derived_instead() -> void:
	# Six beats cannot have produced 900000 bars. The bar fields are derived from the beat
	# count and the meter rather than trusted, so the unreachable state cannot be represented.
	_clock.from_dict({"beats_per_bar": 4, "beat_index": 5, "bar_index": 900000})
	assert_int(_clock.beat_index).is_equal(5)
	assert_int(_clock.bar_index).is_equal(1)
	assert_int(_clock.beat_in_bar).is_equal(1)


func test_a_restored_meter_too_long_to_be_a_bar_is_refused() -> void:
	# Refused rather than clamped, the same way a restored meter of zero is: the clock already
	# holds a meter its section gave it, and that is a better answer than the nearest legal
	# number to one the save should not have held.
	var restore := func() -> void: _clock.from_dict({"beats_per_bar": 1000000})
	await (assert_error(restore).is_push_warning(
		"divisi: restored state has beats_per_bar 1000000, which is not a bar. Keeping 4."
	))
	assert_int(_clock.beats_per_bar).is_equal(4)


func test_a_restored_tempo_that_is_not_a_number_at_all_is_refused() -> void:
	# true read as a float is 1.0, which is a legal tempo of one beat a minute, so nothing
	# downstream could tell that the save did not hold a number.
	var restore := func() -> void: _clock.from_dict({"bpm": true})
	await (assert_error(restore).is_push_warning(
		"divisi: restored state has bpm true, which is not a number. Keeping 120.000000."
	))
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)


func test_restored_counts_that_are_not_whole_numbers_are_refused() -> void:
	# int() truncates a float and parses a string, so a meter of 3.9, a beat index of 4.9 and
	# a skipped count written as text all landed in the clock as though they had been counts.
	_clock.from_dict({"beat_index": 7, "bar_index": 1, "beat_in_bar": 3, "skipped_beats": 2})
	_clock.from_dict({"beats_per_bar": 3.9, "beat_index": 4.9, "skipped_beats": "7"})
	assert_int(_clock.beats_per_bar).is_equal(4)
	assert_int(_clock.beat_index).is_equal(7)
	assert_int(_clock.skipped_beats).is_equal(2)


func test_a_whole_number_written_as_a_float_still_restores() -> void:
	# Every number in a JSON save comes back as a float, so refusing a float outright would
	# refuse the ordinary way a game writes this dictionary to disk. What is refused is a
	# float that is not a whole number.
	_clock.from_dict({"beats_per_bar": 3.0, "beat_index": 8.0, "skipped_beats": 2.0})
	assert_int(_clock.beats_per_bar).is_equal(3)
	assert_int(_clock.beat_index).is_equal(8)
	assert_int(_clock.skipped_beats).is_equal(2)
