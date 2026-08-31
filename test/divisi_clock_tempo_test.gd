extends GdUnitTestSuite

## What happens when the tempo or the meter is written while the clock is already running.
##
## Both are plain [code]@export[/code] properties, so the inspector invites exactly this, and
## a game that speeds the music up under pressure writes them from code. The clock is driven
## by hand at 60 frames per second here, with no audio device, the same way the rest of the
## clock suite is.

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


# Frame i of a 60 fps run is at i / 60.0 seconds. Written as a division rather than as a step
# added up, so that frame 240 is exactly 4.0 and lands on a beat rather than a hair before one.
func _run_frames(from_frame: int, to_frame: int) -> void:
	for i in range(from_frame, to_frame + 1):
		_clock.advance_to(float(i) / 60.0)


func test_a_tempo_of_zero_or_less_is_refused_rather_than_clamped() -> void:
	# A zero tempo divides by zero in every boundary calculation, and the clamp that used to
	# stand in for refusing it, a millionth of a beat per minute, is one beat every 694 days:
	# a clock that looks alive and never emits again. The write is refused, out loud, and the
	# tempo that was already there stays.
	var write_zero := func() -> void: _clock.bpm = 0.0
	await (assert_error(write_zero).is_push_error(
		"divisi: bpm must be greater than 0. Refusing 0.000000, the tempo stays 120.000000."
	))
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)
	_clock.bpm = -60.0
	assert_float(_clock.bpm).is_equal_approx(120.0, 0.000001)


func test_a_meter_of_zero_or_less_is_refused_rather_than_clamped() -> void:
	# The same policy and the same reason: the export hint advertises a minimum of 1, so a 0
	# arriving here came from code, and quietly reading it as 1 hides the mistake.
	var write_zero := func() -> void: _clock.beats_per_bar = 0
	await (assert_error(write_zero).is_push_error(
		"divisi: beats_per_bar must be at least 1. Refusing 0, the meter stays 4."
	))
	assert_int(_clock.beats_per_bar).is_equal(4)
	_clock.beats_per_bar = -3
	assert_int(_clock.beats_per_bar).is_equal(4)


func test_speeding_up_mid_play_does_not_fire_a_burst_of_beats() -> void:
	# The beat grid used to stay anchored where the old tempo had put it, so the beat the new
	# grid claimed the music was on jumped. Doubling the tempo at beat 8 emitted beats 9 to 16
	# in the single frame after the write, and skipped_beats still read 0.
	_clock.start()
	_run_frames(1, 240)
	assert_int(_clock.beat_index).is_equal(8)
	_beats.clear()

	_clock.bpm = 240.0
	# One frame later nothing has jumped.
	_clock.advance_to(241.0 / 60.0)
	assert_array(_beats).is_empty()
	# And the second that follows holds exactly the four beats 240 BPM has in it.
	_run_frames(242, 301)
	assert_array(_beats).is_equal([9, 10, 11, 12])
	assert_int(_clock.skipped_beats).is_equal(0)


func test_slowing_down_mid_play_does_not_leave_a_gap_with_no_beat() -> void:
	# The same anchor, the other way round: quartering the tempo at beat 16 left the new grid
	# reading beat 4, which is behind the count, so nothing was emitted until real time caught
	# up with it. That was 12.98 s of music with no beat in it, and skipped_beats read 0.
	_clock.bpm = 240.0
	_clock.start()
	_run_frames(1, 240)
	assert_int(_clock.beat_index).is_equal(16)
	_beats.clear()

	_clock.bpm = 60.0
	# Four more seconds: at 60 BPM that is four beats, one per second, with no gap.
	_run_frames(241, 480)
	assert_array(_beats).is_equal([17, 18, 19, 20])
	assert_int(_clock.skipped_beats).is_equal(0)


func test_a_meter_written_mid_play_keeps_the_next_bar_on_a_downbeat() -> void:
	# The bar line is counted from the grid anchor, so a meter change left next_boundary()
	# answering with a beat that is not a downbeat at all, and a transition scheduled against
	# it landed inside a bar.
	_clock.start()
	_run_frames(1, 240)
	assert_int(_clock.beat_index).is_equal(8)
	assert_int(_clock.beat_in_bar).is_equal(0)

	_clock.beats_per_bar = 3
	var boundary := _clock.next_boundary(DivisiQuantize.NEXT_BAR)
	var current_downbeat := _clock.beat_index - _clock.beat_in_bar
	assert_int((_clock.beat_at(boundary) - current_downbeat) % _clock.beats_per_bar).is_equal(0)

	# And the bar count carries on, in bars of three from the beat the meter changed on.
	var bars_before := _clock.bar_index
	_bars.clear()
	_run_frames(241, 420)
	assert_array(_bars).is_equal([bars_before + 1, bars_before + 2])


func test_writing_the_same_tempo_every_frame_does_not_hold_the_beat_off() -> void:
	# Re-anchoring moves the grid to now, so doing it on every write would push the next beat
	# one beat into the future every frame and no beat would ever arrive. A game writing the
	# tempo it already has is not changing the tempo.
	_clock.start()
	for i in range(1, 121):
		_clock.bpm = 120.0
		_clock.beats_per_bar = 4
		_clock.advance_to(float(i) / 60.0)
	assert_array(_beats).is_equal([0, 1, 2, 3, 4])
