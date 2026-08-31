extends GdUnitTestSuite

## The parts of a [DivisiPlayer] that a scene sets up rather than calls: what it plays when it
## enters the tree, which bus it plays on, what it hands to the next scene, and the beat and
## bar signals it forwards.

const EXPLORE := preload("res://demo/sections/explore.tres")
const COMBAT := preload("res://demo/sections/combat.tres")

var _bus_index := -1


func after_test() -> void:
	if _bus_index >= 0:
		AudioServer.remove_bus(_bus_index)
		_bus_index = -1
	var state := get_node_or_null(^"/root/DivisiState")
	if state != null:
		state.clear()


func _fresh_player(persist: bool = false) -> DivisiPlayer:
	var player: DivisiPlayer = auto_free(DivisiPlayer.new())
	player.sections = [EXPLORE, COMBAT] as Array[DivisiSection]
	player.persist_across_scenes = persist
	return player


func test_autoplay_starts_its_section_as_the_player_enters_the_tree() -> void:
	var player := _fresh_player()
	player.autoplay = &"combat"
	add_child(player)
	assert_bool(player.playing).is_true()
	assert_object(player.current_section).is_same(COMBAT)
	assert_bool(player.clock.running).is_true()
	player.stop()


func test_an_empty_autoplay_leaves_the_player_silent() -> void:
	# The default. A player that started playing the first section it was given would make the
	# section order load bearing and give a game no way to stay quiet until it is ready.
	var player := _fresh_player()
	add_child(player)
	assert_bool(player.playing).is_false()
	assert_object(player.current_section).is_null()


func test_the_bus_reaches_every_player_the_node_owns() -> void:
	# Written at runtime, after the three AudioStreamPlayer children already exist. The stinger
	# player has to move with the music, or a duck would be ducking against a different bus.
	var player := _fresh_player()
	add_child(player)
	_bus_index = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_bus_index, "DivisiTestBus")

	player.bus = &"DivisiTestBus"
	for node_name in [^"DivisiMusicA", ^"DivisiMusicB", ^"DivisiStinger"]:
		var child := player.get_node(node_name) as AudioStreamPlayer
		assert_str(String(child.bus)).is_equal("DivisiTestBus")

	player.bus = &"Master"


func test_persist_across_scenes_hands_the_music_to_the_next_player(timeout := 20000) -> void:
	# What a scene change does, without changing scene: the player writes its state as it
	# leaves the tree and the next one picks it up as it enters. Nothing else in the suite
	# exercises the flag itself, only capture_state and restore_state by hand.
	var state := get_node_or_null(^"/root/DivisiState")
	state.clear()

	var first := _fresh_player(true)
	add_child(first)
	first.play(&"explore")
	first.intensity = 0.4
	await get_tree().create_timer(0.8).timeout
	var beat_before := first.clock.beat_index
	remove_child(first)
	assert_bool(state.has_state).is_true()

	var second := _fresh_player(true)
	add_child(second)
	assert_bool(second.playing).is_true()
	assert_object(second.current_section).is_same(EXPLORE)
	assert_int(second.clock.beat_index).is_equal(beat_before)
	assert_float(second.intensity).is_equal_approx(0.4, 0.001)
	# One save is restored once: a second player in the same scene must not pick it up again.
	assert_bool(state.has_state).is_false()
	second.stop()


func test_the_player_forwards_the_clocks_beats_and_bars(timeout := 20000) -> void:
	# The class documentation tells you to connect here rather than to the clock, because a
	# section change can leave you holding a stale one. Only the clock's own signals were
	# asserted anywhere, so the forwarding itself was never checked.
	var player := _fresh_player()
	add_child(player)
	var beats: Array[int] = []
	var bars: Array[int] = []
	player.beat.connect(func(index: int) -> void: beats.append(index))
	player.bar.connect(func(index: int) -> void: bars.append(index))

	player.play(&"explore")
	await get_tree().create_timer(2.5).timeout

	assert_array(beats).is_not_empty()
	assert_array(bars).is_not_empty()
	assert_int(beats[0]).is_equal(0)
	assert_int(bars[0]).is_equal(0)
	# The last thing forwarded is where the clock actually is, on both counts.
	assert_int(beats[-1]).is_equal(player.clock.beat_index)
	assert_int(bars[-1]).is_equal(player.clock.bar_index)
	player.stop()
