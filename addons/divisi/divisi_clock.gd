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
signal bar(index: int)

## Volume floor. The engine's own inspector hint for a synchronized stream's volume stops at
## -60 dB ([code]audio_stream_synchronized.cpp:169[/code] at 4.4-stable), so anything at or
## below this is inaudible in practice and is treated as silence.
const SILENCE_DB := -80.0

## A frame that stalls long enough to miss more than this many beats does not emit all of
## them. Emitting a burst of hundreds of beat handlers after a window drag or a level load is
## worse than admitting the gap, so the skipped ones are counted in [member skipped_beats]
## and only the newest beat is emitted.
const MAX_CATCH_UP_BEATS := 16

## Beats per minute of the stream this clock is following.
@export_range(1.0, 400.0, 0.01, "or_greater", "suffix:BPM") var bpm: float = 120.0:
	set(value):
		bpm = maxf(0.000001, value)

## Beats in a bar. 4 is 4/4.
@export_range(1, 32, 1, "or_greater") var beats_per_bar: int = 4:
	set(value):
		beats_per_bar = maxi(1, value)

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

## Beats that a stalled frame skipped over, see [constant MAX_CATCH_UP_BEATS]. Should stay 0.
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

## Seconds in one beat at the current tempo.
var beat_seconds: float:
	get:
		return 60.0 / bpm

## Seconds in one bar at the current tempo.
var bar_seconds: float:
	get:
		return beat_seconds * float(beats_per_bar)

# Musical position at which the current source's timeline begins. A section change moves this
# forward instead of resetting position, so beat and bar indexes keep counting across it.
var _origin: float = 0.0
# Beat index of the beat that sits exactly on _origin.
var _origin_beat: int = 0
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
	_origin_beat = 0
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
## [param at_position] and a [signal bar] is emitted there. The beat that sits on the boundary
## has usually already been emitted by the tick that ran immediately before this call, and it
## is not emitted twice.
func rebase(
	at_position: float,
	source_position: float,
	loop_length: float,
	new_bpm: float = 0.0,
	new_beats_per_bar: int = 0
) -> void:
	# Read against the outgoing grid, before the tempo changes under it.
	var boundary_beat := beat_at(at_position)
	if new_bpm > 0.0:
		bpm = new_bpm
	if new_beats_per_bar > 0:
		beats_per_bar = new_beats_per_bar
	position = maxf(position, at_position + source_position)
	_origin = at_position
	_last_raw = source_position
	_wraps = 0
	_loop_length = maxf(0.0, loop_length)
	running = true

	if beat_index >= boundary_beat:
		# The boundary beat is already out. Keep it, and only announce the new downbeat if
		# that beat was not itself a downbeat, which is the NEXT_BAR case.
		_origin_beat = boundary_beat
		beat_index = boundary_beat
		if beat_in_bar != 0:
			beat_in_bar = 0
			bar_index += 1
			bar.emit(bar_index)
	else:
		# Nothing has been emitted at or past the boundary, so the next tick announces it.
		_origin_beat = beat_index + 1
		beat_index = _origin_beat - 1
		beat_in_bar = beats_per_bar - 1


## Points the clock at a stream that is already playing at [param source_position], without
## moving [member position] or any index. Used when restoring saved state into a fresh scene:
## [method from_dict] puts the counts back, then this re-attaches them to the new playback.
## [param source_position] must be the phase within the loop that playback was started at, so
## that the stream's own first sample keeps sitting on a downbeat.
func resync_source(source_position: float, loop_length: float) -> void:
	_origin = position - source_position
	_origin_beat = beat_index - floori(source_position / beat_seconds)
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
	}


## Puts back counts taken by [method to_dict]. Call [method resync_source] afterwards to
## attach them to the stream that is now playing. Missing keys keep their current values, so a
## dictionary from an older version restores what it can rather than failing.
func from_dict(state: Dictionary) -> void:
	bpm = float(state.get("bpm", bpm))
	beats_per_bar = int(state.get("beats_per_bar", beats_per_bar))
	position = float(state.get("position", position))
	beat_index = int(state.get("beat_index", beat_index))
	bar_index = int(state.get("bar_index", bar_index))
	beat_in_bar = int(state.get("beat_in_bar", beat_in_bar))
	skipped_beats = int(state.get("skipped_beats", skipped_beats))


## Reads the audio device, advances [member position] and emits any beats and bars that were
## crossed. Called from [method Node._process] unless a [DivisiPlayer] owns this clock.
func tick() -> void:
	if not running:
		return
	if player == null or not player.playing:
		return
	advance_to(compensated_position(player))


## The musical position of the next [param quantize] boundary, in the same units as
## [member position].
func next_boundary(quantize: DivisiQuantize.Mode) -> float:
	if quantize == DivisiQuantize.NOW:
		return position
	var beats_since_origin := (position - _origin) / beat_seconds
	var n := floori(beats_since_origin) + 1
	if quantize == DivisiQuantize.NEXT_BAR:
		# _origin always sits on a downbeat: start() begins on one and rebase() re-anchors to
		# the incoming stream's own first sample, which is one.
		while n % beats_per_bar != 0:
			n += 1
	return _origin + float(n) * beat_seconds


## Seconds from now until the next [param quantize] boundary. 0.0 for
## [constant DivisiQuantize.NOW].
func time_to_next(quantize: DivisiQuantize.Mode) -> float:
	return maxf(0.0, next_boundary(quantize) - position)


## The beat index that [param musical_position] falls on, against the current grid.
func beat_at(musical_position: float) -> int:
	return _origin_beat + floori((musical_position - _origin) / beat_seconds)


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

	var target := _origin_beat + floori((position - _origin) / beat_seconds)
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
		beat_in_bar += 1
		var downbeat := beat_in_bar >= beats_per_bar
		if downbeat:
			beat_in_bar = 0
			bar_index += 1
		beat.emit(beat_index)
		if downbeat:
			bar.emit(bar_index)
