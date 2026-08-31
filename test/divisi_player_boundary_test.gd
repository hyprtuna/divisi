extends GdUnitTestSuite

## What a transition or a stinger scheduled for a boundary does when the tempo moves before it
## lands.
##
## Both are scheduled against a beat, announced against a beat, and land at a position. A tempo
## written in between moves where that beat falls: the bar a transition was scheduled for
## arrives sooner at a faster tempo and later at a slower one. The scheduler has to ask again
## rather than keep the position it worked out when it scheduled.
##
## The clock is detached from its player here, so it can be driven a frame at a time with no
## audio device the way the rest of the clock suite is, while [method DivisiPlayer.transition_to]
## and the firing path stay exactly the code the product runs.

const EXPLORE := preload("res://demo/sections/explore.tres")
const COMBAT := preload("res://demo/sections/combat.tres")
const STINGER := preload("res://demo/audio/stinger.ogg")
const LOOP_SECONDS := 16.0

var _announced: int = -99
var _bars: Array[int] = []
var _beats: Array[int] = []
var _beat_in_bars: Array[int] = []
var _stinger_beat: int = -99
# The reading the clock is fed each frame. Up to a landing it is the frame count, because the
# clock has been on one stream since the top of the run. The rebase moves the clock's origin
# onto the boundary, so after a landing the reading is a position inside the incoming stream
# and carries on from the overshoot the rebase dropped it in at. Feeding frame time past that
# point hands the clock a jump the size of the boundary, which bursts out the beats being
# measured for and hides the gap in front of them.
var _raw: float = 0.0


# A player whose clock this suite drives itself. play() starts the real stream players, which
# the headless dummy driver is happy to run, and then the clock is unhooked from them so that
# advance_to() is the only thing that moves musical time.
func _detached_player() -> DivisiPlayer:
	var player := DivisiPlayer.new()
	player.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	player.transition_seconds = 0.0
	add_child(player)
	player.play(&"explore")
	player.clock.player = null
	player.clock.bpm = 120.0
	player.clock.beats_per_bar = 4
	player.clock.start(LOOP_SECONDS)
	_announced = -99
	_bars.clear()
	_beats.clear()
	_beat_in_bars.clear()
	_stinger_beat = -99
	player.transition_started.connect(
		func(_from: StringName, _to: StringName, at_bar: int) -> void: _announced = at_bar
	)
	player.bar.connect(func(index: int) -> void: _bars.append(index))
	player.beat.connect(
		func(index: int) -> void:
			_beats.append(index)
			_beat_in_bars.append(player.clock.beat_in_bar)
	)
	player.stinger_started.connect(func() -> void: _stinger_beat = player.clock.beat_index)
	return player


# One frame: the clock reads its position, then the player does the work that frame is due.
func _frame(player: DivisiPlayer, at_frame: int) -> void:
	player.clock.advance_to(float(at_frame) / 60.0)
	player._process(1.0 / 60.0)


# The same frame, on whatever timeline the clock is currently reading. See _raw.
func _frame_raw(player: DivisiPlayer) -> void:
	_raw += 1.0 / 60.0
	player.clock.advance_to(_raw)
	player._process(1.0 / 60.0)


# One scheduled transition, with a tempo written while it is pending. Returns an empty string
# when the landing keeps every promise the scheduling made, and what it broke when it does not.
func _one_transition(warm: int, new_bpm: float) -> String:
	var player := _detached_player()
	var frame := 0
	for i in range(1, warm + 1):
		frame = i
		_frame(player, frame)

	var boundary_beat := player.clock.next_boundary_beat(DivisiQuantize.NEXT_BAR)
	player.transition_to(&"combat", DivisiQuantize.NEXT_BAR)
	var announced := _announced
	# Everything from here to the landing. Between now and the boundary there is exactly one
	# downbeat, the boundary's own, so exactly one bar signal may cross this window.
	_bars.clear()
	_beats.clear()
	_beat_in_bars.clear()
	player.clock.bpm = new_bpm

	var landed_frame := -1
	var beats_at_landing := -1
	var guard := 0
	_raw = float(frame) / 60.0
	while guard < 4000:
		guard += 1
		frame += 1
		var before := player.current_section.section_name
		_frame_raw(player)
		if landed_frame < 0 and before != player.current_section.section_name:
			landed_frame = frame
			# The landing hands the clock to the incoming stream player; keep it detached.
			player.clock.player = null
			# From here the clock is reading the incoming stream, which the rebase started at
			# its overshoot rather than at the frame count. See _raw.
			_raw = player.clock.source_position
			beats_at_landing = _beats.size()
		# A beat the landing frame itself emitted says nothing about the gap after the landing.
		# When the write pushed the boundary into the past, that frame emits the boundary beat
		# and the beats behind it together, so waiting for the boundary beat to appear ends the
		# settle in the landing frame and measures a gap of zero exactly where there is one.
		# The gap being measured is to the first beat of the new section, so wait for a beat
		# that the landing frame did not already emit.
		if landed_frame >= 0 and _beats.size() > beats_at_landing:
			break

	var settled_bar := player.clock.bar_index
	var boundary_beat_in_bar := -1
	for i in _beats.size():
		if _beats[i] == boundary_beat:
			boundary_beat_in_bar = _beat_in_bars[i]
	var gap_beats := float(frame - landed_frame) / 60.0 / player.clock.beat_seconds
	var bars_seen := _bars.duplicate()
	player.free()

	var broken: Array[String] = []
	if landed_frame < 0:
		broken.append("never landed")
	if settled_bar != announced:
		broken.append("landed in bar %d, announced %d" % [settled_bar, announced])
	var want_bars: Array[int] = [announced]
	if bars_seen != want_bars:
		broken.append("bar signals %s, want [%d]" % [str(bars_seen), announced])
	if boundary_beat_in_bar != 0:
		broken.append(
			"boundary beat %d was beat %d of its bar" % [boundary_beat, boundary_beat_in_bar]
		)
	if gap_beats > 1.2:
		broken.append("first beat %.2f beats after the landing" % gap_beats)
	if broken.is_empty():
		return ""
	return "warm=%d bpm=%.0f: %s" % [warm, new_bpm, ", ".join(broken)]


func test_a_tempo_written_under_a_pending_transition_lands_in_the_bar_it_announced() -> void:
	# The transition fires on a position worked out when it was scheduled, and a tempo write
	# moves the beat that position stood for. Speeding up brought the bar forward and left the
	# scheduler waiting past it: the music landed as much as two bars late, off the downbeat,
	# with the beat signal silent for up to eight beats while the clock caught up with a
	# boundary it had already crossed. Swept wide enough to cross the band that failed.
	var broken: Array[String] = []
	for warm in range(40, 220, 6):
		for new_bpm: float in [60.0, 90.0, 150.0, 200.0, 400.0, 121.0]:
			var report := _one_transition(warm, new_bpm)
			if report != "":
				broken.append(report)
	assert_array(broken).is_empty()


func test_a_stinger_scheduled_for_a_bar_fires_on_that_beat_when_the_tempo_moves() -> void:
	# The same staleness on the stinger, which has carried it since stingers could be
	# quantized: the beat it was scheduled for arrives early at the faster tempo and the
	# stinger waits for a position that beat no longer sits on, so it lands off the bar line
	# it was asked for.
	var wrong: Array[String] = []
	for new_bpm: float in [200.0, 400.0, 90.0]:
		var player := _detached_player()
		var frame := 0
		for i in range(1, 41):
			frame = i
			_frame(player, frame)

		var boundary_beat := player.clock.next_boundary_beat(DivisiQuantize.NEXT_BAR)
		player.play_stinger(STINGER, DivisiQuantize.NEXT_BAR)
		player.clock.bpm = new_bpm

		var guard := 0
		while _stinger_beat == -99 and guard < 4000:
			guard += 1
			frame += 1
			_frame(player, frame)
		var fired_on := _stinger_beat
		player.free()

		if fired_on != boundary_beat:
			wrong.append(
				(
					"bpm=%.0f: stinger scheduled for beat %d fired on beat %d"
					% [new_bpm, boundary_beat, fired_on]
				)
			)
	assert_array(wrong).is_empty()


func test_a_transition_taken_now_is_not_pushed_onto_a_beat() -> void:
	# NOW is not a beat, it is this instant, so it keeps the position it was asked at rather
	# than being derived from a beat number. Deriving it would start the incoming section as
	# much as a beat into its own stems instead of at their top.
	var player := _detached_player()
	for i in range(1, 41):
		_frame(player, i)
	var at := player.clock.position

	player.transition_to(&"combat", DivisiQuantize.NOW)
	_frame(player, 41)

	assert_str(String(player.current_section.section_name)).is_equal("combat")
	# The incoming stems started at the boundary, which was this instant, so the clock's own
	# timeline for them begins there and not at the beat before it.
	assert_float(player.clock.source_position).is_less(1.0 / 30.0)
	assert_float(at).is_greater(0.0)
	player.free()


func test_a_transition_into_a_bar_of_one_lands_in_the_bar_it_announced() -> void:
	# The landing writes the incoming section's tempo and meter into the clock, and on a clock
	# that is still running those are mid play writes. A meter of one is shorter than any beat
	# of the bar the outgoing section was on, so it announces the bar that closes: off the grid
	# being replaced, carrying an index counted from the section being left, ahead of the
	# landing's own bar. One frame long enough to carry the music past the boundary, which is
	# what a level load does, is enough to be on such a beat.
	var player := _detached_player()
	var narrow := DivisiSection.new()
	narrow.section_name = &"narrow"
	narrow.bpm = 120.0
	narrow.beats_per_bar = 1
	# assign() rather than a plain write: Godot 4.4 will not assign an Array typed by script
	# path to one typed by class name, and the parse error that produces is not a test failure,
	# it is a suite that never runs.
	narrow.layers.assign(EXPLORE.layers)
	player.sections = [EXPLORE, COMBAT, narrow] as Array[DivisiSection]
	for i in range(1, 100):
		_frame(player, i)

	assert_bool(player.transition_to(&"narrow", DivisiQuantize.NEXT_BAR)).is_true()
	var announced := _announced
	_bars.clear()

	# Boundary beat 4 sits at 2.0 s; this frame arrives three and a half beats past it.
	player.clock.advance_to(3.7)
	player._process(1.0 / 60.0)
	player.clock.player = null

	assert_str(String(player.current_section.section_name)).is_equal("narrow")
	# One bar signal across the landing, the one the transition named.
	assert_array(_bars).is_equal([announced])
	assert_int(player.clock.bar_index).is_equal(announced)
	player.free()
