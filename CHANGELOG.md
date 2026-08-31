# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/hyprtuna/divisi/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/hyprtuna/divisi/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hyprtuna/divisi/releases/tag/v0.1.0
