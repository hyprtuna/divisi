# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
  engine's own transition table.

- **Stingers.** `DivisiPlayer.play_stinger()` schedules a one-shot over the
  running mix on the next beat or bar, with an optional plain level dip on
  the music while it plays and a configurable release back to full volume.

- **State across scene changes.** A `DivisiPlayer` with
  `persist_across_scenes` set writes its section, intensity and clock
  position into the `DivisiState` autoload as it leaves the tree, and picks
  them back up in the next scene, resuming mid-bar rather than restarting.
  The autoload holds a plain dictionary and nothing else, and does nothing
  unless a player asks it to.

- **A debug overlay.** `DivisiDebug` draws the section, bar and beat, the
  current drift, and every layer's live gain as a small on-screen meter, for
  a `DivisiPlayer` found automatically or assigned directly.

- **A demo project.** Two sections, four stems each, morphed by a threat
  slider, a bar-quantized transition button, a beat-synced pulse next to the
  live audio versus system clock readout, a stinger button and a scene change
  that keeps the music running. The demo audio is CC0, synthesised for this
  project.

- **CI on Godot 4.4 and 4.7.** gdformat and gdlint on every `.gd` file,
  gdUnit4 headless tests on both supported Godot versions, and a check that
  no em or en dash appears anywhere in the repository.

[Unreleased]: https://github.com/hyprtuna/divisi/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hyprtuna/divisi/releases/tag/v0.1.0
