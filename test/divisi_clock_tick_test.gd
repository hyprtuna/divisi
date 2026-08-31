extends GdUnitTestSuite

## [method DivisiClock.tick], the one path that reads a real audio device.
##
## Everything else in the clock suite drives [method DivisiClock.advance_to] by hand, which is
## the point of that method existing. tick() is the wiring between it and an
## [AudioStreamPlayer], and nothing exercised it.

const EXPLORE := preload("res://demo/sections/explore.tres")


func test_tick_without_a_player_or_before_start_does_nothing() -> void:
	# A DivisiPlayer sets clock.player itself, so a clock reached before that happens, or after
	# stop(), has none. Ticking it is a no-op rather than a crash.
	var clock: DivisiClock = auto_free(DivisiClock.new())
	clock.tick()
	assert_int(clock.beat_index).is_equal(-1)
	clock.start()
	clock.tick()
	assert_int(clock.beat_index).is_equal(-1)
	assert_float(clock.position).is_equal_approx(0.0, 0.000001)


func test_tick_advances_the_clock_from_a_playing_player(timeout := 8000) -> void:
	# The clock a DivisiPlayer owns has its own _process turned off, and the player ticks it at
	# the top of its own frame so the transition scheduler reads a position from this frame
	# rather than the last one. This clock is ticked by hand for the same reason.
	var player: DivisiPlayer = auto_free(DivisiPlayer.new())
	player.sections = [EXPLORE] as Array[DivisiSection]
	add_child(player)
	player.play(&"explore")

	var clock: DivisiClock = auto_free(DivisiClock.new())
	clock.player = player.get_node(^"DivisiMusicA") as AudioStreamPlayer
	clock.start(EXPLORE.loop_length())
	await get_tree().create_timer(0.8).timeout

	# Nothing has ticked it, so it has not moved, however long the music has been playing.
	assert_int(clock.beat_index).is_equal(-1)
	clock.tick()
	assert_float(clock.position).is_greater(0.0)
	assert_int(clock.beat_index).is_greater_equal(0)
	player.stop()
