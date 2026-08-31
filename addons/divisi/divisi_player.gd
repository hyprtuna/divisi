class_name DivisiPlayer
extends Node

## Plays adaptive music: layered sections, bar quantized transitions between them, and
## stingers over the top.
##
## divisi does not mix anything. A section plays as one [AudioStreamSynchronized] and the
## engine mixes its layers, reading each layer's volume out of the resource on every mix chunk
## ([code]audio_stream_synchronized.cpp:231[/code] at 4.4-stable, [code]:232[/code] at
## 4.7.2-stable). What this node adds is the part the engine has no answer for: a musical
## clock to schedule against, a single [member intensity] driving every layer's gain through
## its curve, transitions that land on a bar line, and stingers that land on a beat.
##
## Crossfades are scheduled by divisi on its own clock rather than handed to the engine's
## transition table, because that table's fades have open correctness bugs:
## [url=https://github.com/godotengine/godot/issues/94538]94538[/url] pop and mistiming in
## seamless transitions, [url=https://github.com/godotengine/godot/issues/99384]99384[/url]
## breakage when a stream is modified while playing, and
## [url=https://github.com/godotengine/godot/issues/110216]110216[/url] clips that cannot loop.
## All three were open on 2026-08-31.
##
## Two [AudioStreamPlayer] children carry the music so that the outgoing section keeps playing
## until the fade ends, and a third carries stingers. They are created on [method Node._ready]
## and are visible in the remote scene tree as DivisiMusicA, DivisiMusicB and DivisiStinger.

## Emitted when a new section becomes the one being played, that is, when a transition fires,
## not when it is scheduled.
signal section_changed(section_name: StringName)

## Emitted when a transition is scheduled, with the bar index it will land on.
signal transition_started(from_section: StringName, to_section: StringName, at_bar: int)

## Emitted once per beat. Forwarded from [member clock].
signal beat(index: int)

## Emitted on every downbeat. Forwarded from [member clock].
signal bar(index: int)

## Emitted when a scheduled stinger actually starts.
signal stinger_started

## Emitted when the section that was playing reached the end of its stems and stopped, which
## only happens when they are not set to loop. divisi stops rather than sitting on a clock
## that will never advance again.
signal playback_finished(section_name: StringName)

## The sections this player can play, looked up by [member DivisiSection.section_name].
@export var sections: Array[DivisiSection] = []

## Section to start on [method Node._ready]. Empty plays nothing until you call [method play].
@export var autoplay: StringName = &""

## Drives every layer's gain through its [member DivisiLayer.gain] curve, in both the incoming
## and the outgoing section during a crossfade. This is the one knob a game is expected to
## write every frame.
@export_range(0.0, 1.0, 0.001) var intensity: float = 0.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		_apply_intensity()

## Length of a transition crossfade. 0.0 is a hard cut at the boundary.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var transition_seconds: float = 0.5

## Level of the music, before the crossfade and the stinger duck are applied on top. Stingers
## are played at this level too, without the duck.
@export_range(-60.0, 12.0, 0.01, "suffix:dB") var volume_db: float = 0.0:
	set(value):
		volume_db = value
		_apply_volumes()

## Audio bus for the music players and the stinger player.
@export var bus: StringName = &"Master":
	set(value):
		bus = value
		for p in [_music_a, _music_b, _stinger_player]:
			if p != null:
				p.bus = value

## When true, this player writes its section, intensity and musical position into the
## [DivisiState] autoload as it leaves the tree, and picks them back up in the next scene
## instead of starting from the top. Needs the autoload enabled; see the README.
@export var persist_across_scenes: bool = false

## The musical clock. Read [member DivisiClock.position], [member DivisiClock.bar_index] and
## [member DivisiClock.system_clock_offset_seconds] from it. Connect to this player's own
## [signal beat] and [signal bar] rather than to the clock's, so that a section change cannot
## leave you connected to a stale object.
var clock: DivisiClock = null

## The section currently being played, or null.
var current_section: DivisiSection = null

## The section a scheduled transition will move to, or null when nothing is scheduled.
var pending_section: DivisiSection = null

## Whether [method play] has been called and [method stop] has not.
var playing: bool = false

var _music_a: AudioStreamPlayer = null
var _music_b: AudioStreamPlayer = null
var _stinger_player: AudioStreamPlayer = null
# Which of the two music players is the current section, and which is free or fading out.
var _active: AudioStreamPlayer = null
var _idle: AudioStreamPlayer = null
# The section loaded into each music player, so intensity can be applied to both during a
# crossfade against the right layer list.
var _active_section: DivisiSection = null
var _idle_section: DivisiSection = null

# Musical position a scheduled transition fires at, and the beat that position is the
# position of. The beat is what the announced bar was derived from, and it is handed back to
# the clock at the rebase so the bar the music lands in is the bar the announcement named,
# whatever was written to the tempo in between.
var _pending_at: float = 0.0
var _pending_beat: int = 0
# Crossfade in progress: seconds elapsed, and its total length. _fade_seconds of 0 means no
# fade is running.
var _fade_elapsed: float = 0.0
var _fade_seconds: float = 0.0
var _fading: bool = false

# Stinger scheduled but not yet fired.
var _stinger_stream: AudioStream = null
var _stinger_at: float = 0.0
var _stinger_pending: bool = false
# Duck applied to the music while a stinger plays. 0.0 when nothing is ducking.
var _duck_db: float = 0.0
# Seconds of the stinger still to run. Counted down in wall seconds, not in musical time: see
# _advance_duck.
var _duck_hold_remaining: float = 0.0
var _duck_release_seconds: float = 0.25
var _duck_release_from_db: float = 0.0
var _duck_release_elapsed: float = 0.0
var _ducking: bool = false
var _duck_releasing: bool = false
# Requested at schedule time and read at fire time. Kept apart from the active duck above: a
# second stinger scheduled with no duck used to overwrite the depth of a duck that was already
# releasing, which left the release rate at zero and the music permanently quiet.
var _pending_duck_db: float = 0.0
var _pending_duck_release: float = 0.25
# The layers of each slot's section, in mix order, cached so that writing intensity every
# frame does not rebuild the array every frame.
var _active_mixed: Array[DivisiLayer] = []
var _idle_mixed: Array[DivisiLayer] = []


func _ready() -> void:
	_music_a = _make_player(&"DivisiMusicA")
	_music_b = _make_player(&"DivisiMusicB")
	_stinger_player = _make_player(&"DivisiStinger")
	_music_a.finished.connect(_on_music_finished.bind(_music_a))
	_music_b.finished.connect(_on_music_finished.bind(_music_b))
	_active = _music_a
	_idle = _music_b

	clock = DivisiClock.new()
	clock.name = "DivisiClock"
	# This node ticks the clock itself, at the top of its own _process, so that the transition
	# scheduler always reads a position from this frame rather than the previous one.
	clock.set_process(false)
	clock.beat.connect(_on_clock_beat)
	clock.bar.connect(_on_clock_bar)
	add_child(clock)

	if persist_across_scenes and _restore_saved_state():
		return
	if autoplay != &"":
		play(autoplay)


func _exit_tree() -> void:
	if persist_across_scenes:
		_save_state()


func _process(delta: float) -> void:
	if not playing:
		return
	clock.tick()
	_advance_fade(delta)
	_advance_duck(delta)
	_fire_due_work()


## Starts [param section_name], or the section already loaded when the name is empty, from the
## top. Returns false when the section cannot be found. Use [method transition_to] to move
## between sections while the music is running; this one cuts.
func play(section_name: StringName = &"") -> bool:
	if _music_a == null:
		push_error("divisi: play() was called before the player entered the tree.")
		return false
	var section := find_section(section_name) if section_name != &"" else current_section
	if section == null and section_name == &"" and not sections.is_empty():
		section = sections[0]
	if section == null:
		push_error("divisi: no section named '%s'." % section_name)
		return false
	if section.mixed_layers().is_empty():
		push_error(
			(
				(
					"divisi: section '%s' has no layer with a stream, so there would be nothing to "
					+ "mix and no playback position to read musical time from."
				)
				% section.section_name
			)
		)
		return false

	_cancel_pending()
	_stop_players()
	_active = _music_a
	_idle = _music_b
	_load_into(_active, section, 0.0)
	_active_section = section
	_active_mixed = section.mixed_layers()
	_idle_section = null
	_idle_mixed = []
	current_section = section

	clock.player = _active
	clock.bpm = section.bpm
	clock.beats_per_bar = section.beats_per_bar
	clock.start(section.loop_length())
	playing = true
	_apply_volumes()
	section_changed.emit(section.section_name)
	return true


## Stops the music, any scheduled transition and any stinger. The clock stops with it and
## keeps its last counts.
func stop() -> void:
	_cancel_pending()
	_stop_players()
	if clock != null:
		clock.stop()
	playing = false
	current_section = null
	_active_section = null
	_idle_section = null


## Schedules a crossfade to [param section_name] at the next [param quantize] boundary.
##
## Returns false when the section does not exist, or when it is already the one playing and
## nothing is scheduled. Calling it again before the boundary replaces the scheduled
## transition rather than queueing a second one. When nothing is playing yet it is the same as
## [method play].
func transition_to(
	section_name: StringName, quantize: DivisiQuantize.Mode = DivisiQuantize.NEXT_BAR
) -> bool:
	if not playing:
		return play(section_name)
	var section := find_section(section_name)
	if section == null:
		push_error("divisi: no section named '%s'." % section_name)
		return false
	if section == current_section and pending_section == null:
		return false

	pending_section = section
	_pending_beat = clock.next_boundary_beat(quantize)
	_pending_at = clock.next_boundary(quantize)
	transition_started.emit(
		current_section.section_name, section.section_name, clock.landing_bar(_pending_at)
	)
	return true


## Drops a scheduled transition, leaving the section that is playing alone. Returns false when
## nothing was scheduled.
##
## This is the way to change your mind. Calling [method transition_to] with the section already
## playing does not cancel: while something is pending it is accepted, and schedules a
## crossfade from the section to itself.
func cancel_transition() -> bool:
	if pending_section == null:
		return false
	pending_section = null
	return true


## Schedules [param stream] on the stinger player at the next [param quantize] boundary.
##
## [param duck_db] is a plain level dip applied to the music players while the stinger runs,
## recovering over [param release_seconds] once it ends. It is a volume change, not sidechain
## compression: nothing analyses the stinger's envelope, and the music does not breathe with
## it. Pass 0.0 for no duck. Only one stinger can be scheduled at a time; a second call before
## the boundary replaces the first.
##
## A duck only ever lowers the music. A positive [param duck_db] is ignored, with a warning,
## rather than raising it. The dip stops at [constant DivisiClock.SILENCE_DB], the same floor
## the layer gains use, so a very large one is silence rather than a number the audio server
## has to make sense of.
##
## The duck is held for the length of the stinger and then released, and both are counted in
## plain seconds rather than in musical time. The stinger has its own player, so pausing the
## music does not pause it, and a hold measured against a stopped clock would never end.
func play_stinger(
	stream: AudioStream,
	quantize: DivisiQuantize.Mode = DivisiQuantize.NEXT_BEAT,
	duck_db: float = 0.0,
	release_seconds: float = 0.25
) -> bool:
	if stream == null:
		push_error("divisi: play_stinger was given no stream.")
		return false
	if not playing:
		push_error("divisi: play_stinger needs the music running, so there is a beat to land on.")
		return false
	_stinger_stream = stream
	_stinger_at = clock.next_boundary(quantize)
	_stinger_pending = true
	if duck_db > 0.0:
		push_warning(
			(
				(
					"divisi: play_stinger was given duck_db %+f, which would raise the music "
					+ "rather than duck it. Ignoring it."
				)
				% duck_db
			)
		)
	_pending_duck_db = clampf(duck_db, DivisiClock.SILENCE_DB, 0.0)
	_pending_duck_release = maxf(0.0, release_seconds)
	return true


## The section with this name, or null.
func find_section(section_name: StringName) -> DivisiSection:
	for section in sections:
		if section != null and section.section_name == section_name:
			return section
	return null


## Per layer levels of the section being played, in the order the engine mixes them, as an
## array of [code]{"name": StringName, "db": float}[/code]. What [DivisiDebug] draws.
func layer_gains() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _active_section == null:
		return out
	for layer in _active_mixed:
		out.append({"name": layer.layer_name, "db": layer.gain_db(intensity)})
	return out


## Everything needed to pick this player up again in another scene. See [DivisiState].
func capture_state() -> Dictionary:
	if not playing or current_section == null or clock == null:
		return {}
	return {
		"section": String(current_section.section_name),
		"intensity": intensity,
		"clock": clock.to_dict(),
	}


## Restores state taken by [method capture_state], continuing the bar count and dropping the
## stream back in at the phase it was at. Returns false when the state is empty or names a
## section this player does not have.
func restore_state(state: Dictionary) -> bool:
	if state.is_empty() or not state.has("section"):
		return false
	if _music_a == null:
		push_error("divisi: restore_state() was called before the player entered the tree.")
		return false
	var section := find_section(StringName(state["section"]))
	if section == null:
		push_warning(
			(
				"divisi: saved state names section '%s', which this player does not have."
				% state["section"]
			)
		)
		return false

	_cancel_pending()
	_stop_players()
	intensity = float(state.get("intensity", intensity))
	_active = _music_a
	_idle = _music_b

	clock.player = null
	var saved_clock: Dictionary = state.get("clock", {})
	if not saved_clock.has("bpm"):
		clock.bpm = section.bpm
	if not saved_clock.has("beats_per_bar"):
		clock.beats_per_bar = section.beats_per_bar
	clock.from_dict(saved_clock)

	var loop_length := section.loop_length()
	# Where inside the stems playback was, which the save records. It is not the position
	# modulo the loop length: after a transition the stems did not start at position 0, and
	# restoring as though they had put the music a beat out of phase with the beat grid.
	var phase := float(saved_clock.get("source_position", 0.0))
	if loop_length > 0.0:
		phase = fposmod(phase, loop_length)
	else:
		phase = clampf(phase, 0.0, maxf(0.0, section.loop_length()))

	_load_into(_active, section, phase)
	_active_section = section
	_active_mixed = section.mixed_layers()
	_idle_section = null
	_idle_mixed = []
	current_section = section
	clock.player = _active
	clock.resync_source(phase, loop_length)
	playing = true
	_apply_volumes()
	section_changed.emit(section.section_name)
	return true


func _make_player(node_name: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p


# A section whose stems are not set to loop runs out. Without this the player would sit there
# with playing still true, the clock frozen at the last position it read, and any scheduled
# transition waiting for a boundary that can never arrive: a silent hang, and forgetting to
# tick Loop in the import dock is an easy way to reach it.
func _on_music_finished(from_player: AudioStreamPlayer) -> void:
	if not playing or from_player != _active:
		return
	var finished_name := &""
	if current_section != null:
		finished_name = current_section.section_name
		if not current_section.loops():
			push_warning(
				(
					(
						"divisi: section '%s' reached the end of its stems and stopped. Set Loop on "
						+ "the streams in the import dock if it was meant to keep playing."
					)
					% finished_name
				)
			)
	stop()
	playback_finished.emit(finished_name)


func _load_into(player: AudioStreamPlayer, section: DivisiSection, from_position: float) -> void:
	player.stream = section.build_stream(intensity)
	player.play(from_position)


func _stop_players() -> void:
	for p in [_music_a, _music_b, _stinger_player]:
		if p != null:
			p.stop()
			p.stream = null
	_fading = false
	_fade_seconds = 0.0
	_ducking = false
	_duck_releasing = false
	_duck_db = 0.0
	_duck_hold_remaining = 0.0


func _cancel_pending() -> void:
	pending_section = null
	_stinger_pending = false
	_stinger_stream = null


func _fire_due_work() -> void:
	if pending_section != null and clock.position >= _pending_at:
		_fire_transition()
	if _stinger_pending and clock.position >= _stinger_at:
		_fire_stinger()


func _fire_transition() -> void:
	var section := pending_section
	pending_section = null

	# The boundary passed somewhere inside the frame that just ran. Starting the incoming
	# stream at that overshoot rather than at zero puts its first sample back on the boundary,
	# so the section is in phase even though the frame noticed late.
	var overshoot := maxf(0.0, clock.position - _pending_at)
	var loop_length := section.loop_length()
	if loop_length > 0.0:
		overshoot = fposmod(overshoot, loop_length)

	# Starting a second crossfade while one is still running used to snap both players to the
	# endpoints of the new fade, which stepped the surviving section up and the other one to
	# silence in a single frame: two clicks. Beginning the new fade at the point where its
	# curves already hold the current levels keeps both sides continuous, because
	# cos(t) and sin(1 - t) are the same number.
	var carry := 0.0
	if _fading and _fade_seconds > 0.0:
		carry = 1.0 - clampf(_fade_elapsed / _fade_seconds, 0.0, 1.0)

	var outgoing := _active
	var incoming := _idle
	_load_into(incoming, section, overshoot)
	_idle_section = _active_section
	_idle_mixed = _active_mixed
	_active_section = section
	_active_mixed = section.mixed_layers()
	_active = incoming
	_idle = outgoing
	current_section = section

	clock.player = _active
	clock.rebase(
		_pending_at, overshoot, loop_length, section.bpm, section.beats_per_bar, _pending_beat
	)

	_fade_seconds = maxf(0.0, transition_seconds)
	_fade_elapsed = carry * _fade_seconds
	_fading = true
	_apply_volumes()
	if _fade_seconds <= 0.0:
		_end_fade()
	section_changed.emit(section.section_name)


func _fire_stinger() -> void:
	_stinger_pending = false
	var overshoot := maxf(0.0, clock.position - _stinger_at)
	var length := _stinger_stream.get_length()
	_stinger_player.stream = _stinger_stream
	_stinger_player.volume_db = volume_db
	_stinger_player.play(minf(overshoot, maxf(0.0, length - 0.001)))
	if _pending_duck_db < 0.0:
		_ducking = true
		_duck_releasing = false
		_duck_db = _pending_duck_db
		_duck_release_seconds = _pending_duck_release
		_duck_hold_remaining = maxf(0.0, length - overshoot)
		_apply_volumes()
	stinger_started.emit()


func _advance_fade(delta: float) -> void:
	if not _fading:
		return
	_fade_elapsed += delta
	_apply_volumes()
	if _fade_elapsed >= _fade_seconds:
		_end_fade()


func _end_fade() -> void:
	_fading = false
	if _idle != null:
		_idle.stop()
		_idle.stream = null
	_idle_section = null
	_idle_mixed = []
	_apply_volumes()


func _advance_duck(delta: float) -> void:
	if not _ducking:
		return
	if not _duck_releasing:
		# Counted in the seconds the release ramp below already uses, not in musical time. The
		# stinger plays on its own player, so pausing the music stops the clock without
		# stopping the stinger, and a hold measured against a stopped clock never ends: a
		# paused stream used to leave the music 18 dB down for the whole pause and bring it
		# back only afterwards.
		_duck_hold_remaining -= delta
		if _duck_hold_remaining > 0.0:
			return
		_duck_releasing = true
		_duck_release_from_db = _duck_db
		_duck_release_elapsed = 0.0

	# A ramp over elapsed time from the level the duck was actually at, rather than a rate
	# derived from a depth that a later call could have changed underneath it. This always
	# reaches zero and always clears _ducking.
	if _duck_release_seconds <= 0.0:
		_duck_db = 0.0
	else:
		_duck_release_elapsed += delta
		var t := clampf(_duck_release_elapsed / _duck_release_seconds, 0.0, 1.0)
		_duck_db = lerpf(_duck_release_from_db, 0.0, t)
	if is_zero_approx(_duck_db) or _duck_release_seconds <= 0.0:
		_duck_db = 0.0
		_ducking = false
		_duck_releasing = false
	_apply_volumes()


func _apply_volumes() -> void:
	if _active == null:
		return
	var base := volume_db + _duck_db
	if not _fading:
		_active.volume_db = base
		return
	# Equal power: the two gains are the cosine and sine of a quarter turn, so their squares
	# sum to one and the crossfade holds a constant perceived level rather than dipping in the
	# middle the way two linear ramps do.
	var t := 1.0 if _fade_seconds <= 0.0 else clampf(_fade_elapsed / _fade_seconds, 0.0, 1.0)
	_active.volume_db = base + _gain_db(sin(t * PI * 0.5))
	if _idle != null:
		_idle.volume_db = base + _gain_db(cos(t * PI * 0.5))


func _apply_intensity() -> void:
	_apply_stream_intensity(_active, _active_mixed)
	if _fading:
		_apply_stream_intensity(_idle, _idle_mixed)


# Takes the layer list rather than the section: intensity is expected to be written every
# frame, and rebuilding the filtered array on every write allocated once a frame per player.
func _apply_stream_intensity(player: AudioStreamPlayer, mixed: Array[DivisiLayer]) -> void:
	if player == null or mixed.is_empty():
		return
	var sync := player.stream as AudioStreamSynchronized
	if sync == null:
		return
	for i in mini(mixed.size(), sync.stream_count):
		sync.set_sync_stream_volume(i, mixed[i].gain_db(intensity))


func _restore_saved_state() -> bool:
	var state := get_node_or_null(^"/root/DivisiState")
	if state == null:
		push_warning(
			"divisi: persist_across_scenes is on but the DivisiState autoload is not enabled."
		)
		return false
	return restore_state(state.take())


func _save_state() -> void:
	var state := get_node_or_null(^"/root/DivisiState")
	if state == null:
		return
	state.put(capture_state())


func _on_clock_beat(index: int) -> void:
	beat.emit(index)


func _on_clock_bar(index: int) -> void:
	bar.emit(index)


static func _gain_db(amplitude: float) -> float:
	if amplitude <= 0.0:
		return DivisiClock.SILENCE_DB
	return maxf(DivisiClock.SILENCE_DB, linear_to_db(amplitude))
