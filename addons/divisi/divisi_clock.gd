class_name DivisiClock
extends Node

## Musical time for one [AudioStreamPlayer], with [signal beat] and [signal bar] signals.
##
## The engine has no musical clock and emits no beat or bar signal. Verified by grepping
## [code]modules/interactive_music/[/code] at the tags [code]4.4-stable[/code] and
## [code]4.7.2-stable[/code]: the only [code]emit_signal[/code] in the module is
## [code]parameter_list_changed[/code], an editor facing [Resource] signal.
## [url=https://github.com/godotengine/godot/pull/81542]PR 81542[/url], which would add beat
## and bar getters, has been open since 2023-09-11;
## [url=https://github.com/godotengine/godot-proposals/issues/8937]proposal 8937[/url], filed
## by a core developer, has been open since 2024-01-22. This node is the stand in.
##
## Position is read from the audio device, not from frame deltas:
## [codeblock]
## position = player.get_playback_position()
##          + AudioServer.get_time_since_last_mix()
##          - AudioServer.get_output_latency()
## [/codeblock]
## which is the formula in the engine's own
## [url=https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html]Sync the
## gameplay with audio and music[/url] tutorial. That page warns that accumulating
## [code]delta[/code] instead drifts, "as the sound hardware clock is never exactly in sync
## with the system clock". [member system_clock_offset_seconds] reports how far apart the two
## clocks are running right now, so the difference can be watched rather than assumed.
##
## Signals fire from [method Node._process], so they are frame accurate and latency
## compensated, not sample accurate. Sample accurate scheduling needs engine support that
## does not exist yet; see proposal 8937.

## Emitted once per beat, in order, with a running index that starts at 0 on [method start].
## [member beat_in_bar] is already updated when this fires.
signal beat(index: int)

## Emitted on every downbeat, immediately after the [signal beat] for that downbeat, with a
## running index that starts at 0 on [method start].
##
## Two things move the bar line onto a beat that has already been emitted: a section change,
## whose incoming stems begin at their own downbeat, and a meter shrunk to one while the music
## is between downbeats. Both announce it where it happens rather than holding it back until
## the next beat, so a downbeat is never read off [member beat_in_bar] without having been
## announced.
signal bar(index: int)

## Volume floor. The engine's own inspector hint for a synchronized stream's volume stops at
## -60 dB ([code]audio_stream_synchronized.cpp:169[/code] at 4.4-stable), so anything at or
## below this is inaudible in practice and is treated as silence.
const SILENCE_DB := -80.0

## A frame that stalls long enough to miss this many beats or more does not emit all of
## them. Emitting a burst of hundreds of beat handlers after a window drag or a level load is
## worse than admitting the gap, so the skipped ones are counted in [member skipped_beats]
## and only the newest beat is emitted.
const MAX_CATCH_UP_BEATS := 16

## The longest bar a meter may describe. The inspector hint stops at 32 and this is far past
## any meter in use, but a bar does have to end: at 120 BPM a bar of a million beats is 5787
## days, which is the same clock that looks alive and never emits again that a tempo of a
## millionth of a beat per minute is, one bar line up.
const MAX_BEATS_PER_BAR := 1024

## The largest beat or bar count [method from_dict] will restore. Over four years of unbroken
## play at 400 BPM, the fastest tempo the inspector hint suggests, and far enough below the
## largest 64 bit integer that the counts can still be advanced past it. Restored at that
## integer they could not be: the next beat overflowed the count, and the clock, having read
## a beat index that its own arithmetic could never exceed, never emitted again.
const MAX_RESTORED_COUNT := 1000000000

## Beats per minute of the stream this clock is following.
##
## Writing this while the clock is running is a tempo change, and the beat grid re-anchors to
## the beat that was last emitted: the counts carry on from where they are, the beat after the
## write is one beat of the new tempo away from the beat before it, and nothing is emitted
## twice. The current beat is cut short or stretched, which is what a tempo change is.
##
## Writing it on consecutive frames is a ramp, and ramps through: because the grid is pinned to
## the last beat rather than to the position of each write, a beat that is already part way
## through is not pushed away again by the next write, and the beats land at roughly the tempo
## the ramp is passing through as it passes through it.
##
## Zero, negative, and anything that is not a finite number are refused with an error rather
## than clamped. A clamp to a millionth of a beat per minute is one beat every 694 days: a
## clock that looks alive and never emits again. [constant @GDScript.NAN] is worse, because
## every comparison against it is false, so the next boundary is NAN and a pending transition
## can never fire; [constant @GDScript.INF], which [code]60.0 / interval[/code] reaches
## whenever the interval is zero, makes the beat a length of nothing.
@export_range(1.0, 400.0, 0.01, "or_greater", "suffix:BPM") var bpm: float = 120.0:
	set(value):
		if not is_finite(value):
			push_error(
				(
					"divisi: bpm must be a finite number. Refusing %s, the tempo stays %f."
					% [value, bpm]
				)
			)
			return
		if value <= 0.0:
			push_error(
				(
					"divisi: bpm must be greater than 0. Refusing %f, the tempo stays %f."
					% [value, bpm]
				)
			)
			return
		var changed := not is_equal_approx(value, bpm)
		bpm = value
		if changed:
			_reanchor_running_grid()

## Beats in a bar. 4 is 4/4.
##
## Writing this while the clock is running re-anchors the bar line the same way [member bpm]
## does, so the bar the music is in finishes on the new meter rather than on the old one, and
## [method next_boundary] keeps answering with a real downbeat.
##
## Shrinking it past the beat of the bar the music is on moves the count to the last beat of
## the new bar, so that bar ends at the next beat rather than running on to where the old bar
## line was. Shrinking it to 1 is the one case with nowhere to move to, because every beat of
## a bar of one is a downbeat: the bar the write closed is announced there and then, with a
## [signal bar].
##
## Zero or negative is refused with an error rather than clamped, the same as [member bpm], and
## so is anything past [constant MAX_BEATS_PER_BAR]. A meter is an int, so a non-finite value
## written here arrives as the smallest 64 bit integer and the first of those guards catches
## it.
@export_range(1, 32, 1, "or_greater") var beats_per_bar: int = 4:
	set(value):
		if value <= 0:
			push_error(
				(
					"divisi: beats_per_bar must be at least 1. Refusing %d, the meter stays %d."
					% [value, beats_per_bar]
				)
			)
			return
		if value > MAX_BEATS_PER_BAR:
			push_error(
				(
					"divisi: beats_per_bar must be at most %d. Refusing %d, the meter stays %d."
					% [MAX_BEATS_PER_BAR, value, beats_per_bar]
				)
			)
			return
		var changed := value != beats_per_bar
		beats_per_bar = value
		if changed:
			_reanchor_running_grid()

## The player to read musical time from. When a [DivisiPlayer] owns the clock it sets this
## itself and drives [method tick] directly, so that the clock is always read before the
## transition scheduler looks at it.
@export var player: AudioStreamPlayer = null

## Musical seconds since [method start], monotonically increasing. Survives stream loops and
## section changes; it is not the stream's playback position.
var position: float = 0.0

## Index of the most recently emitted beat, or -1 before the first one.
var beat_index: int = -1

## Index of the most recently emitted bar, or -1 before the first one.
var bar_index: int = -1

## Which beat of the current bar the most recent [signal beat] was, from 0 to
## [member beats_per_bar] - 1.
var beat_in_bar: int = -1

## Beats that a stalled frame skipped over rather than emitting, see
## [constant MAX_CATCH_UP_BEATS]. In steady play it stays 0. It is expected to move after a
## level load, and after the scene tree is unpaused, because the audio server keeps mixing
## while [method Node._process] is not running.
var skipped_beats: int = 0

## Whether [method start] has been called and [method stop] has not.
var running: bool = false

## The gap between the two clocks a game could drive music from: the audio device's, minus
## the system's. Musical time this clock has counted, minus the wall clock time that passed.
##
## divisi counts the first. A musical clock written as [code]_position += delta[/code] counts
## the second. This number is how far apart their answers are right now, and only one of them
## matches what the player can hear.
##
## How far apart they run is a property of the machine, not of divisi, so do not read a small
## value as a pass or a large one as a bug. Measured over ten minutes of PulseAudio playback on
## one Linux box, sampled every 30 seconds, it held between -33 and -15 ms: a band 18 ms wide,
## with no trend across the run. The beat count stayed exactly on the music throughout: at 120
## BPM beat 1200 landed at position 600.04 s, with nothing skipped. The engine's own
## [url=https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html]audio sync
## tutorial[/url] warns that on other hardware it does not stay put, because "the sound
## hardware clock is never exactly in sync with the system clock, [so] the timing information
## will slowly drift away". divisi is unaffected either way: it never reads the system clock
## for musical time.
##
## Two details make this measure the clocks rather than something else. Both terms are sampled
## at the last [method advance_to], not at the moment you read this: reading a live wall clock
## against a position last written a frame ago measures how long ago the frame was, and a
## 200 ms hitch alone moved this by 166 ms. And the baseline is taken at the first tick after
## playback is actually running, not at [method start]: a player takes a moment to prime its
## buffers, and on a real device that showed up as a fixed 190 ms offset that was start up
## time, not two clocks running apart.
var system_clock_offset_seconds: float:
	get:
		if not running or not _baselined:
			return 0.0
		var wall := float(_last_tick_usec - _wall_start_usec) / 1000000.0
		return (position - _wall_start_position) - wall

## Where inside the current stream playback is, in seconds, counting from the sample
## [method start] or [method rebase] put on [member position]'s timeline. This is what a
## restore has to hand back to [method resync_source]: after a transition it is not
## [member position] modulo the loop length, because the stream did not start at position 0.
var source_position: float:
	get:
		var elapsed := position - _origin
		if _loop_length > 0.0:
			return fposmod(elapsed, _loop_length)
		return maxf(0.0, elapsed)

## Seconds in one beat at the current tempo.
var beat_seconds: float:
	get:
		return 60.0 / bpm

## Seconds in one bar at the current tempo.
var bar_seconds: float:
	get:
		return beat_seconds * float(beats_per_bar)

# Musical position at which the current source's timeline begins. A section change moves this
# forward instead of resetting position, so beat and bar indexes keep counting across it. This
# is the stream's anchor: source_position and the loop wrap count are measured from it.
var _origin: float = 0.0
# Musical position the beat grid is anchored at, with the beat index that sits exactly on it.
# Normally the same point as _origin, because start(), rebase() and resync_source() lay both
# down together. A tempo or meter written while the clock is running moves this one alone: the
# grid above the stream changed, the stream under it did not restart.
var _grid_at: float = 0.0
var _grid_beat: int = 0
# Which beat of the bar the beat on the grid anchor is. Zero after start() and rebase(), which
# both anchor on a downbeat; resync_source() and a mid play meter change can land anywhere.
var _grid_beat_in_bar: int = 0
# Where on the grid the beat that was last emitted sits. Not where the clock was when it
# noticed: the frame that emits a beat runs a fraction of a beat after the beat itself, and
# what the re-anchor below needs is the beat, not the frame.
var _last_beat_at: float = 0.0
# Raw playback position last seen, used to notice a loop wrap.
var _last_raw: float = 0.0
# Completed loops of the current source.
var _wraps: int = 0
# Length of one loop of the current source, or 0.0 when it does not loop.
var _loop_length: float = 0.0
# Wall clock reading at the first tick of this run, for system_clock_offset_seconds.
var _wall_start_usec: int = 0
# Whether that baseline has been taken yet.
var _baselined: bool = false
# Wall clock reading at the last advance_to, so system_clock_offset_seconds compares two
# readings taken at the same instant.
var _last_tick_usec: int = 0
# Musical position at start, for system_clock_offset_seconds.
var _wall_start_position: float = 0.0


func _process(_delta: float) -> void:
	# A clock owned by a DivisiPlayer is ticked by that player instead, in a fixed order.
	# See DivisiPlayer._process.
	tick()


## Begins counting from zero. [param loop_length] is the length of one loop of the stream in
## seconds, which lets the clock keep counting past a loop point; pass 0.0 for a stream that
## does not loop. Emits [signal beat] 0 and [signal bar] 0 on the next tick.
func start(loop_length: float = 0.0) -> void:
	position = 0.0
	beat_index = -1
	bar_index = -1
	beat_in_bar = beats_per_bar - 1
	skipped_beats = 0
	_origin = 0.0
	_grid_at = 0.0
	_grid_beat = 0
	_grid_beat_in_bar = 0
	_last_beat_at = 0.0
	_last_raw = 0.0
	_wraps = 0
	_loop_length = maxf(0.0, loop_length)
	_baselined = false
	running = true


## Stops counting. [member position] and the indexes keep their last values.
func stop() -> void:
	running = false


## Moves the clock onto a new stream without resetting [member position] or the beat and bar
## indexes, so a section change does not restart the count. [param at_position] is the musical
## position the new stream's first sample lands on, and [param source_position] is where
## inside the new stream playback actually started, which is the overshoot between the
## boundary and the frame that noticed it.
##
## The incoming stems begin at their own downbeat, so the bar grid re-anchors to
## [param at_position] and a [signal bar] is emitted there, once. The beat that sits on the
## boundary has usually already been emitted by the tick that ran immediately before this
## call, and it is not emitted twice.
##
## [member beat_index] is never moved backwards. A frame long enough to overshoot the boundary
## by more than one beat has already emitted beats past it, and rewinding the counter so they
## could be emitted again fired every beat handler twice with a decreasing index.
##
## [param at_beat] is the beat [param at_position] is the position of, as
## [method next_boundary_beat] returned it when the transition was scheduled. Passing it is
## what keeps the announced bar and the landed bar the same number: the default, -1, reads the
## beat back off [param at_position] instead, which is exact but answers against whatever grid
## is in place by the time the boundary arrives rather than the one that was scheduled against.
##
## Leaves the clock running, whether or not it was running before.
func rebase(
	at_position: float,
	source_position: float,
	loop_length: float,
	new_bpm: float = 0.0,
	new_beats_per_bar: int = 0,
	at_beat: int = -1
) -> void:
	# Read against the outgoing grid, before the tempo changes under it. A caller that
	# scheduled against [method next_boundary_beat] passes that beat back here, so the bar it
	# announced then and the bar the music lands in now are the same number even if a tempo
	# write moved the grid in between. -1 asks for it to be read off at_position instead.
	var boundary_beat := beat_at(at_position) if at_beat < 0 else at_beat
	# Whether the tick just before this call announced the boundary as a downbeat, which is
	# what a NEXT_BAR transition does. If it did, announcing it again is a duplicate.
	var downbeat_already_out := beat_index == boundary_beat and beat_in_bar == 0

	if new_bpm > 0.0:
		bpm = new_bpm
	if new_beats_per_bar > 0:
		beats_per_bar = new_beats_per_bar
	position = maxf(position, at_position + source_position)
	_origin = at_position
	_grid_at = at_position
	_grid_beat = boundary_beat
	_grid_beat_in_bar = 0
	_last_raw = source_position
	_wraps = 0
	_loop_length = maxf(0.0, loop_length)
	running = true

	if beat_index < boundary_beat:
		# Nothing has been emitted at or past the boundary, so the next tick announces it.
		beat_index = boundary_beat - 1
		beat_in_bar = beats_per_bar - 1
		_last_beat_at = position_of_beat(beat_index)
		return

	beat_in_bar = (beat_index - _grid_beat) % beats_per_bar
	_last_beat_at = position_of_beat(beat_index)
	if not downbeat_already_out:
		bar_index += 1
		bar.emit(bar_index)


## Points the clock at a stream that is already playing at [param source_position], without
## moving [member position] or any index. Used when restoring saved state into a fresh scene:
## [method from_dict] puts the counts back, then this re-attaches them to the new playback.
## [param source_position] must be the position inside the stream that playback was started
## at, which [method to_dict] records for exactly this purpose.
##
## Unlike [method start] and [method rebase], the position this anchors the grid at is not a
## downbeat: after a transition, a stream's own first sample and the bar line are different
## beats, and for a loop that is not a whole number of bars they move apart at every wrap. So
## the beat of the bar that [param source_position] lands on is recorded alongside it, and
## [method next_boundary] uses it rather than assuming zero.
func resync_source(source_position: float, loop_length: float) -> void:
	var beats_in := floori(source_position / beat_seconds)
	_origin = position - source_position
	_grid_at = _origin
	_grid_beat = beat_index - beats_in
	_grid_beat_in_bar = posmod(beat_in_bar - beats_in, beats_per_bar)
	_last_beat_at = position_of_beat(beat_index)
	_last_raw = source_position
	_wraps = 0
	_loop_length = maxf(0.0, loop_length)
	_baselined = false
	running = true


## The clock's counts, for carrying across a scene change. See [DivisiState].
func to_dict() -> Dictionary:
	return {
		"bpm": bpm,
		"beats_per_bar": beats_per_bar,
		"position": position,
		"beat_index": beat_index,
		"bar_index": bar_index,
		"beat_in_bar": beat_in_bar,
		"skipped_beats": skipped_beats,
		"source_position": source_position,
	}


## Puts back counts taken by [method to_dict]. Call [method resync_source] afterwards to
## attach them to the stream that is now playing. Missing keys keep their current values, so a
## dictionary from an older version restores what it can rather than failing.
##
## Every value is checked against what playing can actually produce, and a value outside that
## is refused or clamped with a [method @GlobalScope.push_warning] naming the field. This
## dictionary is the one input divisi takes from outside itself, and SECURITY.md names it as
## the surface worth scrutinising: a beat index of -500, or a beat of the bar past the end of
## the bar, is a state no amount of playing could reach, and every boundary this clock answers
## afterwards is derived from it.
##
## A field that does not hold a number of the right kind is refused and the clock keeps what it
## has. A whole number written as a float is a count, because a JSON save writes every number
## that way, but 3.9 is not, and neither is [code]true[/code] or the string "7": those used to
## arrive as 3, 1.0 BPM and 7 with nothing said. A number that is finite but outside the range
## playing reaches is clamped, or, where the clock already holds a good value from its section,
## refused in favour of that.
##
## [member bar_index] and [member beat_in_bar] are not restored blind. They are not free
## numbers: a bar is announced with a beat, so there cannot be more bars than beats, and the
## beat of the bar cannot sit past the end of the bar. Where the dictionary breaks that, they
## are derived from [member beat_index] and [member beats_per_bar] instead, so a bar count no
## run of that many beats could have reached cannot be represented at all.
func from_dict(state: Dictionary) -> void:
	if state.has("bpm"):
		var restored_bpm: Variant = state["bpm"]
		if not _is_number(restored_bpm):
			push_warning(
				(
					"divisi: restored state has bpm %s, which is not a number. Keeping %f."
					% [restored_bpm, bpm]
				)
			)
		elif not is_finite(float(restored_bpm)) or float(restored_bpm) <= 0.0:
			push_warning(
				(
					"divisi: restored state has bpm %s, which is not a tempo. Keeping %f."
					% [restored_bpm, bpm]
				)
			)
		else:
			bpm = float(restored_bpm)
	if state.has("beats_per_bar"):
		var restored_beats: Variant = state["beats_per_bar"]
		if not _is_whole_number(restored_beats):
			push_warning(
				(
					"divisi: restored state has beats_per_bar %s, which is not a count. Keeping %d."
					% [restored_beats, beats_per_bar]
				)
			)
		elif int(restored_beats) < 1 or int(restored_beats) > MAX_BEATS_PER_BAR:
			push_warning(
				(
					"divisi: restored state has beats_per_bar %s, which is not a bar. Keeping %d."
					% [restored_beats, beats_per_bar]
				)
			)
		else:
			beats_per_bar = int(restored_beats)
	position = _restored_float(state, "position", position, 0.0)
	beat_index = _restored_int(state, "beat_index", beat_index, -1, MAX_RESTORED_COUNT)
	bar_index = _restored_int(state, "bar_index", bar_index, -1, MAX_RESTORED_COUNT)
	beat_in_bar = _restored_int(state, "beat_in_bar", beat_in_bar, -1, MAX_RESTORED_COUNT)
	skipped_beats = _restored_int(state, "skipped_beats", skipped_beats, 0, MAX_RESTORED_COUNT)
	_derive_bar_fields()


## Reads the audio device, advances [member position] and emits any beats and bars that were
## crossed. Called from [method Node._process] unless a [DivisiPlayer] owns this clock.
func tick() -> void:
	if not running:
		return
	if player == null or not player.playing:
		return
	advance_to(compensated_position(player))


## The beat index of the next [param quantize] boundary.
##
## This is the number to schedule against. [method next_boundary] is this beat turned into a
## position, and a position is what a scheduler has to compare [member position] against, but
## the beat is what the bar count is derived from at both ends: announced when the transition
## is scheduled, and landed on when [method rebase] re-anchors the grid. Carrying it through
## rather than reading it back off the position is what stops the two disagreeing.
func next_boundary_beat(quantize: DivisiQuantize.Mode) -> int:
	if quantize == DivisiQuantize.NOW:
		return beat_at(position)
	var n := beat_at(position) - _grid_beat + 1
	if quantize == DivisiQuantize.NEXT_BAR:
		# The anchor is a downbeat after start() and rebase(), but not after resync_source() or
		# a mid play meter change, so the bar line is counted from the beat of the bar the
		# anchor actually sits on.
		while posmod(_grid_beat_in_bar + n, beats_per_bar) != 0:
			n += 1
	return _grid_beat + n


## The musical position of the next [param quantize] boundary, in the same units as
## [member position].
func next_boundary(quantize: DivisiQuantize.Mode) -> float:
	if quantize == DivisiQuantize.NOW:
		return position
	return position_of_beat(next_boundary_beat(quantize))


## The musical position beat [param beat] falls on, against the current grid.
##
## The inverse of [method beat_at], and the expression [method beat_at] corrects itself
## against, so a position this returns reads back as the beat it was asked for.
func position_of_beat(beat: int) -> float:
	return _grid_at + float(beat - _grid_beat) * beat_seconds


## Seconds from now until the next [param quantize] boundary. 0.0 for
## [constant DivisiQuantize.NOW].
func time_to_next(quantize: DivisiQuantize.Mode) -> float:
	return maxf(0.0, next_boundary(quantize) - position)


## The bar index the music will be in once a section change lands on [param musical_position].
##
## That is the bars crossed between now and the boundary, plus the downbeat that
## [method rebase] announces when it re-anchors the grid there. A boundary that is already a
## downbeat on the current grid is not counted twice.
func landing_bar(musical_position: float) -> int:
	var boundary_beat := beat_at(musical_position)
	var bar_started_at := beat_index - beat_in_bar
	var crossed := (boundary_beat - bar_started_at) / beats_per_bar
	var lands_on_a_downbeat := (
		posmod(boundary_beat - _grid_beat + _grid_beat_in_bar, beats_per_bar) == 0
	)
	return bar_index + maxi(0, crossed) + (0 if lands_on_a_downbeat else 1)


## The beat index that [param musical_position] falls on, against the current grid: the last
## beat whose [method position_of_beat] is at or before it.
##
## Dividing the distance from the grid anchor by the beat length answers that, but only up to
## a rounding error. Building a boundary position out of a beat number and taking it apart
## again is a round trip through a float, and it loses an ulp: on a grid anchored at 0.0, or at
## a boundary rebase() had itself produced, it never showed, but a tempo written mid play
## anchors the grid on an arbitrary position and from there one boundary in five came back as
## the beat before it. The division is a first guess, out by at most one, and it is corrected
## against the same expression the position was built with rather than nudged past the error by
## an epsilon: an epsilon moves where this breaks, it does not stop it breaking.
func beat_at(musical_position: float) -> int:
	var beat := _grid_beat + floori((musical_position - _grid_at) / beat_seconds)
	if position_of_beat(beat + 1) <= musical_position:
		return beat + 1
	if position_of_beat(beat) > musical_position:
		return beat - 1
	return beat


## Latency compensated playback position of [param from_player], in seconds.
static func compensated_position(from_player: AudioStreamPlayer) -> float:
	return compensate(
		from_player.get_playback_position(),
		AudioServer.get_time_since_last_mix(),
		AudioServer.get_output_latency()
	)


## The audio sync arithmetic on its own, so it can be checked without an audio device.
##
## [param raw] is the playback position the player reports, which is where the mixer has got
## to rather than what you can hear. [param since_last_mix] is how long ago the audio thread
## last filled a buffer, and [param output_latency] is how long already mixed audio still
## takes to reach the speakers. Adding the first and subtracting the second is what the
## engine's audio sync tutorial prescribes.
##
## [param since_last_mix] is bounded by [param output_latency] before it is used. That term
## exists to cover audio mixed but not yet played, and the output latency is the whole depth of
## that pipeline, so a larger value does not describe audio that is really further along: it
## means the audio thread has not run. Feeding it in unbounded pushes the clock permanently
## forward, because [method advance_to] never lets time go back. Measured under the headless
## dummy driver, which mixes on the main thread: a stalled frame reported its entire length as
## audio progress, and the clock kept it. On a real device the value stays well inside this
## bound and nothing changes.
##
## Clamped at zero: on the first frames of playback the latency term is larger than the
## position, and negative musical time is not a thing.
static func compensate(raw: float, since_last_mix: float, output_latency: float) -> float:
	var latency := maxf(0.0, output_latency)
	var mixed_ahead := clampf(since_last_mix, 0.0, latency)
	return maxf(0.0, raw + mixed_ahead - latency)


## Advances the clock to [param raw], a playback position inside the current stream in
## seconds, and emits every beat and bar that crossing it passed.
##
## [method tick] calls this with the latency compensated position of [member player]. It
## touches neither [AudioServer] nor a player itself, so the whole of the clock's behaviour
## can be driven from another source of musical time, and can be tested headless where there
## is no audio device to read. Does nothing while the clock is stopped.
func advance_to(raw: float) -> void:
	if not running:
		return

	# A loop wrap sends the playback position from near the end of the stream back to near
	# zero. Only a jump backwards of more than half a loop is read as one; a smaller backwards
	# step is device jitter, which the monotonic clamp below absorbs.
	if _loop_length > 0.0 and raw + _loop_length * 0.5 < _last_raw:
		_wraps += 1
	_last_raw = raw

	# Musical time never runs backwards. get_time_since_last_mix() is an estimate that can
	# overshoot, so two consecutive reads can disagree by a millisecond or so in the wrong
	# direction, and a beat handler that sees time reverse fires the same beat twice.
	#
	# The cost is that the clock tracks the upper envelope of the device's jitter rather than
	# its mean, so it sits biased high by roughly the jitter amplitude. On a real device that
	# is well under a millisecond, and it is a fixed offset rather than something that
	# accumulates. Firing a beat twice is the worse failure.
	position = maxf(position, _origin + raw + float(_wraps) * _loop_length)
	_last_tick_usec = Time.get_ticks_usec()
	if not _baselined:
		_baselined = true
		_wall_start_usec = _last_tick_usec
		_wall_start_position = position

	var target := beat_at(position)
	if target <= beat_index:
		return

	if target - beat_index > MAX_CATCH_UP_BEATS:
		# Move the whole grid forward rather than replaying the gap. The bar count has to jump
		# with it: bar_index is which bar the music is in, not how many bars were announced,
		# and a stall must not leave it reading a bar behind the audio for the rest of the run.
		var jumped := target - beat_index - 1
		skipped_beats += jumped
		var into_bar := beat_in_bar + jumped
		beat_in_bar = into_bar % beats_per_bar
		bar_index += into_bar / beats_per_bar
		beat_index = target - 1

	while beat_index < target:
		beat_index += 1
		_last_beat_at = position_of_beat(beat_index)
		beat_in_bar += 1
		var downbeat := beat_in_bar >= beats_per_bar
		if downbeat:
			beat_in_bar = 0
			bar_index += 1
		beat.emit(beat_index)
		if downbeat:
			bar.emit(bar_index)


# Moves the beat grid onto the beat the music last emitted, keeping the counts where they are.
# This is the arithmetic rebase() uses at a section boundary, with the boundary being the beat
# that just went out and the stream underneath left alone.
#
# Without it a tempo written mid play left the grid anchored to the old tempo, and the beat the
# new grid claimed the music was on jumped: doubling the tempo emitted the whole jump as a
# burst of beats in one frame, halving it waited the jump out in silence, and skipped_beats
# reported 0 either way.
#
# The anchor is the last beat rather than the position of the write. Anchoring on the write is
# right once, and wrong on every frame after the first: it puts the next beat a whole new tempo
# beat past the write, so a second write a frame later puts it a whole beat past that one, and
# a game ramping the tempo over consecutive frames, which is the obvious reason to write bpm
# every frame at all, pushed the next beat away for the length of the ramp and heard nothing
# while skipped_beats read 0. Pinned to the last beat the grid keeps the beat that is already
# part way through, so a ramp emits beats at roughly the tempo it is passing through, and a
# single write still puts the next beat one new beat after the one before it.
func _reanchor_running_grid() -> void:
	if not running or beat_index < 0:
		# Nothing has been emitted yet, so there is no count to keep and the grid start() laid
		# down is still the right one.
		return
	# A beat cannot have been emitted in the future, whatever grid it was emitted against.
	_grid_at = minf(_last_beat_at, position)
	_grid_beat = beat_index
	# A meter that just got shorter can leave the beat of the bar past the end of the new bar.
	# The bar finishes as soon as the new meter allows rather than claiming a downbeat here:
	# the count moves to the last beat of the new bar, so the next beat is the downbeat.
	#
	# A bar of one has no position that is not a downbeat, so there the count cannot avoid
	# reading as one. Reading 0 on its own would say the beat that has just sounded was a
	# downbeat when nothing was ever told it was, so the bar the shrink closed is announced
	# instead, the way rebase() announces the one it re-anchors on. The alternative, leaving
	# the count past the end of the bar, is the state from_dict() refuses to restore because
	# playing cannot produce it, and playing should not start producing it here.
	var shortened := mini(beat_in_bar, beats_per_bar - 1)
	var closes_a_bar := shortened == 0 and beat_in_bar != 0
	beat_in_bar = shortened
	_grid_beat_in_bar = beat_in_bar
	if closes_a_bar:
		bar_index += 1
		bar.emit(bar_index)


# The bar fields, checked against the beat count rather than trusted, and derived from it where
# they do not fit. What is derived is the state a run of this many beats in this meter reaches
# from start(), which is the only answer available once the saved one has been shown to be
# impossible.
func _derive_bar_fields() -> void:
	# Before the first beat, start() leaves the count one short of the first downbeat and no
	# bar announced, and that is the only state a clock can be in there.
	var reachable_bar := -1
	var reachable_beat_in_bar := beats_per_bar - 1
	var bar_fits := bar_index == -1
	# Two values mean no beat has been emitted yet: the -1 a clock carries before start() is
	# called at all, and the one short of a downbeat that start() itself leaves.
	var beat_in_bar_fits := beat_in_bar == -1 or beat_in_bar == beats_per_bar - 1
	if beat_index >= 0:
		reachable_bar = beat_index / beats_per_bar
		reachable_beat_in_bar = beat_index % beats_per_bar
		bar_fits = bar_index >= 0 and bar_index <= beat_index
		beat_in_bar_fits = (
			beat_in_bar >= 0 and beat_in_bar < beats_per_bar and beat_in_bar <= beat_index
		)
	if not bar_fits:
		push_warning(
			(
				(
					"divisi: restored state has bar_index %d, which %d beats in a bar of %d cannot "
					+ "have announced. Using %d."
				)
				% [bar_index, beat_index + 1, beats_per_bar, reachable_bar]
			)
		)
		bar_index = reachable_bar
	if not beat_in_bar_fits:
		push_warning(
			(
				(
					"divisi: restored state has beat_in_bar %d, which is not where beat %d of a bar "
					+ "of %d falls. Using %d."
				)
				% [beat_in_bar, beat_index, beats_per_bar, reachable_beat_in_bar]
			)
		)
		beat_in_bar = reachable_beat_in_bar


# Whether a restored field holds a number at all. A dictionary read off disk can hold anything,
# and float() reads true as 1.0 while int() parses a string, so without this a save that never
# held a tempo restored as a tempo of one beat a minute with nothing said.
static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


# Whether a restored field holds a count. Every number in a JSON save comes back as a float, so
# a float that is a whole number is one; 3.9 is not, and neither is a non-finite one.
static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and is_equal_approx(number, floorf(number))


# One restored integer count, refused when the field does not hold one and clamped to the range
# playing can produce when it does. The field is named in every warning because the caller is a
# game handing divisi a dictionary it may have read off disk, and "the clock is wrong" is not
# something anyone can act on.
#
# The range is compared before the conversion to an int, not after: a float far past the
# largest 64 bit integer converts to the smallest one, which would clamp a count that was much
# too high to the lowest value playing starts from.
static func _restored_int(
	state: Dictionary, key: String, current: int, lowest: int, highest: int
) -> int:
	if not state.has(key):
		return current
	var value: Variant = state[key]
	if not _is_whole_number(value):
		push_warning(
			(
				"divisi: restored state has %s %s, which is not a count. Keeping %d."
				% [key, value, current]
			)
		)
		return current
	var number := float(value)
	if number < float(lowest):
		push_warning(
			(
				"divisi: restored state has %s %s, below the %d that playing starts from. Clamping."
				% [key, value, lowest]
			)
		)
		return lowest
	if number > float(highest):
		push_warning(
			(
				"divisi: restored state has %s %s, past the %d that playing can reach. Clamping."
				% [key, value, highest]
			)
		)
		return highest
	return int(value)


# The same, for a count that is measured in seconds. A non-finite one is refused rather than
# clamped: there is no nearest number of seconds to infinity.
static func _restored_float(state: Dictionary, key: String, current: float, lowest: float) -> float:
	if not state.has(key):
		return current
	var value: Variant = state[key]
	if not _is_number(value) or not is_finite(float(value)):
		push_warning(
			(
				"divisi: restored state has %s %s, which is not a number of seconds. Keeping it."
				% [key, value]
			)
		)
		return current
	var seconds := float(value)
	if seconds >= lowest:
		return seconds
	push_warning(
		(
			"divisi: restored state has %s %f, below the %f that playing starts from. Clamping."
			% [key, seconds, lowest]
		)
	)
	return lowest
