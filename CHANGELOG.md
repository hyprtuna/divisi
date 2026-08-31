# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-08-31

The round that follows 0.1.1's tempo work. Writing `bpm` while the music runs
was a defined thing in 0.1.1 and it opened a hole underneath the bar count:
a transition taken after a tempo write announced one bar and landed the music
in another about one time in five. That is fixed, along with the finiteness
holes on either side of it and the two duck edges that shared their shape.
Nothing in the API changed shape. Two methods were added.

### Fixed

- **A boundary and the beat it lands on are the same beat.**
  `next_boundary()` built a position out of a beat number and `rebase()` took
  it apart again to get the beat back, and that round trip through a float
  loses an ulp. Anchored on 0.0, or on a boundary `rebase()` had produced, it
  never showed. A tempo written mid play anchors the grid on an arbitrary
  position, and from there the boundary read back as the beat before it:
  swept over 228 warm up and tempo pairs, 46 announced one bar and landed in
  the next, with a spurious `bar` signal and a `bar_index` that stayed one out
  for the rest of the run. A save taken across a tempo change inherited the
  same skew through `resync_source()`, 21 of 80. The beat is now the number
  that travels, and the position is derived from it.

- **A tempo ramp keeps the beat instead of silencing it.** Re-anchoring the
  grid on the position of the write is right once and wrong on every frame
  after: the next write pushed the beat that was already due a whole new beat
  further away, and the frame after pushed it again. A four second ramp from
  120 to 240 BPM at 60 fps emitted zero beats with eight owed, and
  `skipped_beats` read 0 throughout. The grid is pinned to the beat that was
  last emitted, so a ramp now emits beats at roughly the tempo it is passing
  through: the same ramp emits twelve.

- **A tempo that is not a finite number is refused.** The guard was "greater
  than 0", which is false for `NAN` and for `INF`, so both walked through it.
  `NAN` made every boundary NAN, and a pending transition could never fire
  because `position >= NAN` is false as well. `INF`, which `60.0 / interval`
  reaches whenever the interval is zero, made the beat a length of nothing.
  A meter longer than `DivisiClock.MAX_BEATS_PER_BAR` is refused on the same
  argument, one bar line up.

- **`from_dict()` now really does refuse or clamp every field with a warning
  naming it.** 0.1.1 said so and seven fields did. An `INF` tempo, an `INF`
  position, a beat index of 9223372036854775807, a bar count of 900000
  alongside five beats, a meter of a million, a tempo of `true` and a meter of
  3.9 all went in silently. Each field is now checked for holding a number of
  the right kind before its range is looked at; a whole number written as a
  float is still a count, because that is how a JSON save writes every number.
  `bar_index` and `beat_in_bar` are derived from the beat count and the meter
  where the dictionary contradicts them, so a bar count no run of that many
  beats could have announced cannot be represented.

- **The stinger duck is counted in seconds the game cannot stretch.** The hold
  ran on the delta `_process` is handed, which `Engine.time_scale` scales,
  while the stinger's own audio is not scaled. At a tenth speed a 1.2 second
  stinger held an 18 dB duck for 13.90 wall seconds. It is read off
  `Time.get_ticks_usec()` now: the same measurement is 1.39. One frame may
  contribute at most `DivisiPlayer.MAX_DUCK_FRAME_SECONDS`, so a frame that
  did not run cannot release the duck under a stinger still to play.

- **A duck depth or release that is not a number is refused.**
  `release_seconds = NAN` wedged the duck at depth for the rest of the run and
  logged "Volume can't be set to NaN" every frame, because nothing NAN touches
  ever compares its way back to zero. `duck_db = NAN` did nothing and said
  nothing, while `+12` dB was already refused out loud. Both now get that same
  warning, naming the value.

- **Shrinking the meter does not claim a downbeat nobody was told about.**
  `beats_per_bar = 1` written at beat 3 of a bar of four gave `mini(3, 0)`,
  so the readout said the beat that had just sounded was a downbeat while no
  `bar` signal had gone out for it. A bar of one has no position that is not a
  downbeat, so the bar the write closes is announced there and then. Meters
  above 1 are unchanged.

### Added

- `DivisiClock.next_boundary_beat()` answers with the beat index of the next
  boundary, and `DivisiClock.position_of_beat()` turns a beat into a position.
  Schedule against the beat: `DivisiClock.rebase()` takes it as an optional
  argument, and passing it is what keeps the bar a transition announced and
  the bar it lands in the same number when the tempo moves in between.

### Changed

- The `bar` signal documents that a section change and a meter shrunk to one
  both announce a downbeat on a beat that has already been emitted, rather
  than holding it back until the next beat.

- The duck documentation says which kind of pause is which. Writing
  `stream_paused` on the music yourself stops the clock and leaves the stinger
  playing, which is what the wall clock hold is for. Pausing the tree stops
  both players, so the stinger, the music and the hold stop and resume
  together.

## [0.1.1] - 2026-08-31

A correctness round. Nothing in the API changed shape, but a tempo written
while the music is running now behaves, the overlay stops printing a time
signature it cannot know, the stinger duck has ends and edges, and the two
regression tests that certified nothing have been made to fail against the
defects they were written for.

### Fixed

- **A tempo written mid play re-anchors the beat grid.** `bpm` and
  `beats_per_bar` are exported properties, so the inspector invites writing
  them while the music runs. The beat grid stayed anchored to the old tempo,
  so the beat the new grid claimed the music was on jumped: 120 to 240 at
  beat 8 emitted eight beats in the single frame after the write, and 240 to
  60 left 12.98 seconds of music with no beat in it. `skipped_beats` read 0
  both ways. The grid now re-anchors where the write happened, so the counts
  carry on with no burst and no gap, and `next_boundary()` keeps answering
  with a real downbeat after a meter change.

- **A tempo or meter of zero or less is refused rather than clamped.**
  `bpm = 0.0` became a millionth of a beat per minute, which is one beat
  every 694 days: a clock that looks alive and never emits again.
  `beats_per_bar = 0` became 1. Both now `push_error` and leave the value
  alone, the same policy a section with no usable layer already had.

- **Restored state is checked against what playing can produce.**
  `DivisiClock.from_dict()` accepted a beat index of -500 and a beat of the
  bar of 99 inside a bar of 4, states nothing could play into, and every
  boundary answered afterwards came from them. Each field is now refused or
  clamped with a warning naming it. A state dictionary is the one input
  divisi takes from outside itself.

- **The debug overlay no longer invents a time signature.** It printed
  `beats_per_bar` as both the numerator and the denominator, so a bar of
  three rendered as "3/3" and a bar of seven as "7/7", correct only in 4/4.
  A `DivisiClock` carries no note value, so the denominator was never
  knowable. The line says "3 beats/bar" now.

- **The stinger duck ends even when the music is paused.** The hold was
  measured against musical time, which stops when the music does, so pausing
  the stream held the music 18 dB down for the whole pause. The hold is
  counted in the same plain seconds the release ramp already used.

- **A duck that is not a duck says so.** A positive `duck_db` was swallowed
  in silence by `minf(0.0, duck_db)`; it is ignored with a warning now. A
  very large one reached `volume_db` unfloored; it stops at
  `DivisiClock.SILENCE_DB`, the floor the layer gains already use.

- **The README quickstart runs as written.** It called an undefined
  `get_threat_level()`, which is a parse error, so the snippet failed before
  its first line. A test now compiles the block straight out of the README.

- **RhythmNotifier's owner is `michaelgundlach`.** The comparison table had a
  spelling that 404s.

### Changed

- The two-player limit says what it costs. The levels do stay continuous
  across a cut taken mid fade, but both players sit at 0.707 amplitude there,
  so the outgoing section stops at that level and the incoming one starts at
  it rather than fading in from silence.

- CI checks that a failing test really fails the run. The workflow claimed
  that had been verified by hand and nothing enforced it; a copy of the
  project with one deliberately failing test in it must now exit 100.

- CONTRIBUTING asks for the red output of a new test rather than only its
  existence, and records that gdUnit4 6.x abandons a suite file at its first
  failure while 5.x does not, so the two matrix legs disagree about the total
  when something is red.

### Added

- Tests for the public surface that had none: `DivisiPlayer.autoplay`,
  `.bus` and `.persist_across_scenes`, `DivisiClock.tick()`, the player's own
  forwarded `beat` and `bar` signals, `DivisiDebug`, and the autoload
  contract `plugin.gd` carries. The suite goes from 93 cases to 126.

## [0.1.0] - 2026-08-31

First release. divisi plays adaptive music on top of Godot 4.3+'s own
`AudioStreamSynchronized`: a musical clock the engine does not provide, and
the scheduling that clock makes possible.

### Added

- **A musical clock.** `DivisiClock` reads musical time from the audio
  device rather than from accumulated frame deltas, so its beat and bar counts
  sit exactly on the music for as long as the music plays. It emits `beat` and
  `bar` signals, keeps a running beat and bar count across section changes and
  stream loops, survives a stalled frame without replaying a burst of missed
  beats, and reports how far the audio device's clock and the system clock have
  run apart, so the difference between the two ways of writing this can be
  watched rather than assumed.

- **Intensity-driven layers.** A `DivisiSection` is a tempo, a time signature
  and an array of `DivisiLayer` resources, each a stem and a `Curve` mapping
  a single `intensity` value, from 0 to 1, to that layer's gain in
  decibels. `DivisiPlayer.intensity` drives every layer of the section
  currently playing, and both sides of a crossfade, every frame.

- **Bar-quantized section transitions.** `DivisiPlayer.transition_to()`
  schedules a crossfade to another section at the next beat or bar boundary,
  or immediately, and the incoming stems land in phase on that boundary
  rather than restarting from zero. Crossfades run on divisi's own clock,
  as an equal-power fade between two players, rather than through the
  engine's own transition table. `transition_started` reports the bar the
  music will actually be in when it lands, and `cancel_transition()` drops a
  scheduled one.

- **Stingers.** `DivisiPlayer.play_stinger()` schedules a one-shot over the
  running mix on the next beat or bar, with an optional plain level dip on
  the music while it plays and a configurable release back to full volume.

- **State across scene changes.** A `DivisiPlayer` with
  `persist_across_scenes` set writes its section, intensity and clock
  position into the `DivisiState` autoload as it leaves the tree, and picks
  them back up in the next scene, resuming mid-bar rather than restarting.
  The autoload holds a plain dictionary and nothing else, and does nothing
  unless a player asks it to.

- **A debug overlay.** `DivisiDebug` draws the section, bar and beat and
  every layer's live gain as a small on-screen meter, for a `DivisiPlayer`
  found automatically or assigned directly. The gap between the audio clock
  and the system clock is available as an opt-in line.

- **Loud failures instead of quiet ones.** A section whose stems are not set
  to loop stops and emits `playback_finished` rather than freezing the clock
  on a boundary that can never arrive, and a section with no usable layer is
  refused by `play()` rather than reporting success and never advancing.

- **A demo project.** Two sections, four stems each, morphed by a threat
  slider, a bar-quantized transition button, a beat-synced pulse next to the
  live audio versus system clock readout, a stinger button and a scene change
  that keeps the music running. The demo audio is CC0, synthesised for this
  project.

- **CI on Godot 4.4 and 4.7.** gdformat and gdlint on every `.gd` file,
  gdUnit4 headless tests on both supported Godot versions, and a check that
  no em or en dash appears anywhere in the repository.

[Unreleased]: https://github.com/hyprtuna/divisi/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/hyprtuna/divisi/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hyprtuna/divisi/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hyprtuna/divisi/releases/tag/v0.1.0
