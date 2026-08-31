extends GdUnitTestSuite

## Which beat a boundary falls on, and the bar a transition scheduled against it lands in.
##
## [method DivisiClock.next_boundary] answers with a position, and [method DivisiClock.rebase]
## reads the beat back off that position, so the two have to agree about which beat it is.
## While the grid was anchored on 0.0 or on a boundary [method DivisiClock.rebase] had itself
## produced, they always did. A tempo written mid play anchors it on an arbitrary position, and
## from there the round trip through a float came back one beat short often enough to matter:
## the transition announced one bar and the music landed in the next.
##
## Driven by hand at 60 frames per second, with no audio device, the same way the rest of the
## clock suite is.

const LOOP_SECONDS := 16.0

var _bars: Array[int] = []


func _fresh(tempo: float, meter: int) -> DivisiClock:
	var clock := DivisiClock.new()
	clock.bar.connect(func(index: int) -> void: _bars.append(index))
	clock.bpm = tempo
	clock.beats_per_bar = meter
	return clock


# Frame i of a 60 fps run is at i / 60.0 seconds, written as a division rather than as a step
# added up so that the frames land where a real one would.
func _run_to(clock: DivisiClock, from_frame: int, to_frame: int) -> void:
	for i in range(from_frame, to_frame + 1):
		clock.advance_to(float(i) / 60.0)


# One warm up at 120 BPM, one tempo write, one NEXT_BAR transition. Returns an empty string
# when the bar that was announced is the bar the music landed in, and a description of the
# disagreement when it is not.
func _one_transition(warm: int, new_bpm: float) -> String:
	var clock := _fresh(120.0, 4)
	clock.start(LOOP_SECONDS)
	_bars.clear()
	_run_to(clock, 1, warm)
	clock.bpm = new_bpm
	var frame := warm
	_run_to(clock, frame + 1, frame + 40)
	frame += 40

	var at := clock.next_boundary(DivisiQuantize.NEXT_BAR)
	var announced := clock.landing_bar(at)
	while clock.position < at:
		frame += 1
		clock.advance_to(float(frame) / 60.0)
	var overshoot := clock.position - at

	# Only the bars the rebase itself emits. The tick that crossed the boundary has already
	# announced the downbeat there, so a second one is a duplicate.
	_bars.clear()
	clock.rebase(at, overshoot, LOOP_SECONDS, new_bpm, 4)
	var landed := clock.bar_index
	var landed_beat_in_bar := clock.beat_in_bar
	var emitted := _bars.duplicate()
	clock.free()

	if landed == announced and landed_beat_in_bar == 0 and emitted.is_empty():
		return ""
	return (
		(
			"warm=%d new_bpm=%.0f boundary=%.12f: announced bar %d, landed bar %d, "
			+ "beat_in_bar %d, bar signals %s"
		)
		% [warm, new_bpm, at, announced, landed, landed_beat_in_bar, str(emitted)]
	)


func test_a_tempo_written_mid_play_lands_the_transition_in_the_bar_it_announced() -> void:
	# Swept wide enough to cross the band this used to fail in: 46 of these 228 pairs
	# announced one bar and landed in another, all of them because the boundary position
	# read back as the beat before the boundary.
	var wrong: Array[String] = []
	for warm in range(30, 200, 3):
		for new_bpm: float in [90.0, 150.0, 60.0, 200.0]:
			var report := _one_transition(warm, new_bpm)
			if report != "":
				wrong.append(report)
	assert_array(wrong).is_empty()


func test_a_transition_with_no_tempo_change_is_the_control_for_that_sweep() -> void:
	# The same sweep with the tempo left alone, which was clean before this fix and has to
	# stay clean after it: the defect was the re-anchored grid, not transitions in general.
	var wrong: Array[String] = []
	for warm in range(30, 200, 3):
		var report := _one_transition(warm, 120.0)
		if report != "":
			wrong.append(report)
	assert_array(wrong).is_empty()


# The bar line of a clock is congruent with its beat grid when the next downbeat is a whole
# number of bars away from the downbeat the current bar started on. Returns that remainder,
# which is 0 for every state playing can produce.
func _bar_line_offset(clock: DivisiClock) -> int:
	var next_downbeat := clock.beat_at(clock.next_boundary(DivisiQuantize.NEXT_BAR))
	return posmod(next_downbeat - (clock.beat_index - clock.beat_in_bar), clock.beats_per_bar)


func test_a_state_saved_across_a_tempo_change_restores_onto_the_same_bar_line() -> void:
	# resync_source() rebuilds the grid from the beat the save recorded, so a save taken while
	# the grid sat on an arbitrary position used to come back a beat out of phase with its own
	# bar line: 21 of these 80 combinations, and none of them without the tempo change.
	var wrong: Array[String] = []
	for change_frame: int in [90, 120, 150, 210, 240]:
		for new_bpm: float in [90.0, 150.0, 240.0, 60.0]:
			for after: int in [30, 75, 130, 200]:
				var clock := _fresh(120.0, 4)
				clock.start(LOOP_SECONDS)
				_run_to(clock, 1, change_frame)
				clock.bpm = new_bpm
				_run_to(clock, change_frame + 1, change_frame + after)
				var live := _bar_line_offset(clock)
				var saved := clock.to_dict()
				clock.free()

				var restored := _fresh(120.0, 4)
				restored.from_dict(saved)
				restored.resync_source(float(saved["source_position"]), LOOP_SECONDS)
				var back := _bar_line_offset(restored)
				restored.free()

				if live != 0 or back != 0:
					(
						wrong
						. append(
							(
								"change_frame=%d new_bpm=%.0f after=%d: live offset %d, restored offset %d"
								% [change_frame, new_bpm, after, live, back]
							)
						)
					)
	assert_array(wrong).is_empty()


func test_the_beat_a_boundary_is_asked_for_is_the_beat_it_reads_back_as() -> void:
	# The invariant underneath both sweeps, asserted directly on a grid re-anchored at an
	# arbitrary position. An epsilon in beat_at() would move where this breaks rather than
	# stop it breaking, so the position is built from the beat number and taken apart with the
	# same expression it was built with.
	var wrong: Array[String] = []
	for warm in range(30, 200):
		var clock := _fresh(120.0, 4)
		clock.start(LOOP_SECONDS)
		_run_to(clock, 1, warm)
		clock.bpm = 200.0
		_run_to(clock, warm + 1, warm + 7)
		for quantize: DivisiQuantize.Mode in [DivisiQuantize.NEXT_BEAT, DivisiQuantize.NEXT_BAR]:
			var wanted := clock.next_boundary_beat(quantize)
			var got := clock.beat_at(clock.next_boundary(quantize))
			if got != wanted:
				wrong.append(
					(
						"warm=%d quantize=%d: asked for beat %d, read back %d"
						% [warm, quantize, wanted, got]
					)
				)
		clock.free()
	assert_array(wrong).is_empty()


func test_a_tempo_written_after_a_transition_is_scheduled_does_not_move_its_bar() -> void:
	# The scheduler announces a bar when the transition is scheduled and lands it a frame or
	# more later. A tempo write in between re-anchors the grid, so the position it scheduled
	# against no longer names the beat it was scheduled for. Carrying the beat number through
	# to the rebase is what keeps the two the same number.
	var clock := _fresh(120.0, 4)
	clock.start(LOOP_SECONDS)
	_run_to(clock, 1, 100)

	var boundary_beat := clock.next_boundary_beat(DivisiQuantize.NEXT_BAR)
	var at := clock.next_boundary(DivisiQuantize.NEXT_BAR)
	var announced := clock.landing_bar(at)
	# Everything from here to the landing, so that the downbeat is counted once wherever it
	# comes from. Speeding the music up pulls the boundary beat earlier than the position the
	# transition was scheduled against, so the tick that crosses it announces the bar and the
	# rebase must not announce it again; slowing down puts it the other way round.
	_bars.clear()

	# The game speeds the music up while the transition is still pending.
	clock.bpm = 150.0
	var frame := 100
	while clock.position < at:
		frame += 1
		clock.advance_to(float(frame) / 60.0)
	var overshoot := clock.position - at
	clock.rebase(at, overshoot, LOOP_SECONDS, 150.0, 4, boundary_beat)
	# One more frame, read off the incoming stream the way the player reads it: a rebase moves
	# the clock's origin onto the boundary, so what it is fed from here is the position inside
	# the new stream, which starts at the overshoot. The write moved the grid, so the beat the
	# boundary was scheduled for is still a frame away, and it is that beat, not whichever one
	# the stale boundary position now points at, that carries the downbeat.
	clock.advance_to(overshoot + 1.0 / 60.0)

	assert_int(clock.beat_index).is_equal(boundary_beat)
	assert_int(clock.bar_index).is_equal(announced)
	assert_int(clock.beat_in_bar).is_equal(0)
	assert_array(_bars).is_equal([announced])
	clock.free()
