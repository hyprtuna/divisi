extends GdUnitTestSuite

## What a player emits while it is loading, as opposed to while it is playing.
##
## Loading a save or a section writes the tempo and the meter into the clock. On a clock that
## is still running those writes are a mid play tempo or meter change, which re-anchors the
## beat grid and, when the incoming meter is shorter than the beat of the bar the outgoing
## state was on, announces the bar that change closes. That announcement is correct when the
## music performed the change and wrong when it did not: nothing sounded, and the bar index it
## carries is counted off the state being replaced.
##
## The clock is driven by hand here, detached from its player, the way the rest of the clock
## suite is driven.

const EXPLORE := preload("res://demo/sections/explore.tres")
const COMBAT := preload("res://demo/sections/combat.tres")
const LOOP_SECONDS := 16.0

var _bars: Array[int] = []
var _beats: Array[int] = []


# A player part way through a bar of four, with signals being recorded from here on.
func _mid_bar_player() -> DivisiPlayer:
	var player := DivisiPlayer.new()
	player.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	add_child(player)
	player.play(&"explore")
	player.clock.player = null
	player.clock.bpm = 120.0
	player.clock.beats_per_bar = 4
	player.clock.start(LOOP_SECONDS)
	for i in range(1, 100):
		player.clock.advance_to(float(i) / 60.0)
		player._process(1.0 / 60.0)
	_bars.clear()
	_beats.clear()
	player.bar.connect(func(index: int) -> void: _bars.append(index))
	player.beat.connect(func(index: int) -> void: _beats.append(index))
	return player


# A save taken in a bar of [param meter], well past where the live clock is.
func _save(meter: int, beat_index: int, beat_in_bar: int) -> Dictionary:
	return {
		"section": "explore",
		"intensity": 0.5,
		"clock":
		{
			"bpm": 120.0,
			"beats_per_bar": meter,
			"position": 20.0,
			"beat_index": beat_index,
			"bar_index": beat_index / meter,
			"beat_in_bar": beat_in_bar,
			"skipped_beats": 0,
			"source_position": 0.0,
		}
	}


func test_restoring_a_save_does_not_announce_a_bar_off_the_state_it_replaces() -> void:
	# The live clock is on beat 3 of a bar of four. The save is a bar of one, which is shorter
	# than that, so writing the meter through its setter closed the outgoing bar and announced
	# it. A listener saw a downbeat that never sounded, and then the restored count, so the bar
	# signal went 0, 1, 41.
	var player := _mid_bar_player()
	assert_int(player.clock.beat_in_bar).is_equal(3)

	assert_bool(player.restore_state(_save(1, 40, 0))).is_true()

	assert_array(_bars).is_empty()
	assert_array(_beats).is_empty()
	assert_int(player.clock.beats_per_bar).is_equal(1)
	assert_int(player.clock.beat_index).is_equal(40)
	player.free()


func test_loading_a_section_does_not_announce_a_bar_off_the_section_it_replaces() -> void:
	# play() writes the incoming section's tempo and meter into the clock before starting it,
	# and the clock is still running from the outgoing section while it does. The same write,
	# the same phantom downbeat, on the path a game takes far more often than a restore.
	var player := _mid_bar_player()
	var narrow := DivisiSection.new()
	narrow.section_name = &"narrow"
	narrow.bpm = 120.0
	narrow.beats_per_bar = 1
	# assign() rather than a plain write: Godot 4.4 will not assign an Array typed by script
	# path to one typed by class name, and the parse error that produces is not a test failure,
	# it is a suite that never runs.
	narrow.layers.assign(EXPLORE.layers)
	player.sections = [EXPLORE, COMBAT, narrow] as Array[DivisiSection]

	assert_bool(player.play(&"narrow")).is_true()

	assert_array(_bars).is_empty()
	assert_array(_beats).is_empty()
	assert_int(player.clock.beats_per_bar).is_equal(1)
	player.free()


func test_a_restore_that_lands_mid_bar_picks_the_count_up_on_the_next_boundary() -> void:
	# Silence during the load must not cost the first bar after it. The save is on beat 42 of a
	# bar of four, two beats in, so the next downbeat is two beats away and has to arrive.
	var player := _mid_bar_player()
	assert_bool(player.restore_state(_save(4, 42, 2))).is_true()
	player.clock.player = null
	_bars.clear()
	_beats.clear()

	# 1.5 s of the restored stream, which at 120 BPM is three beats.
	for i in range(1, 91):
		player.clock.advance_to(float(i) / 60.0)
		player._process(1.0 / 60.0)

	# Beat 43 finishes the restored bar, 44 opens the next one and is announced as its
	# downbeat, 45 is the beat after it. The save was in bar 10, so the bar that arrives is 11.
	assert_array(_beats).is_equal([43, 44, 45])
	assert_array(_bars).is_equal([11])
	assert_int(player.clock.beat_in_bar).is_equal(1)
	player.free()


func test_a_meter_shrunk_while_the_music_plays_still_announces_the_bar_it_closes() -> void:
	# The guard on the other side. Silencing a load must not silence a meter change the music
	# really did perform: that one closes a bar and says so.
	var player := _mid_bar_player()

	player.clock.beats_per_bar = 1

	assert_array(_bars).is_equal([1])
	assert_int(player.clock.beat_in_bar).is_equal(0)
	player.free()
