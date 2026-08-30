extends GdUnitTestSuite

## The autoload that carries music state across a scene change. It holds a Dictionary and
## nothing else, so these are the tests that matter: that it hands state over exactly once,
## and that it does not share a reference with the player that stored it.

const StateScript := preload("res://addons/divisi/divisi_state.gd")

var _state: Node


func before_test() -> void:
	_state = auto_free(StateScript.new())


func test_a_fresh_state_holds_nothing() -> void:
	assert_bool(_state.has_state).is_false()
	assert_dict(_state.take()).is_empty()


func test_put_then_take_round_trips() -> void:
	_state.put({"section": "combat", "intensity": 0.7})
	assert_bool(_state.has_state).is_true()
	var out: Dictionary = _state.take()
	assert_str(out["section"]).is_equal("combat")
	assert_float(out["intensity"]).is_equal_approx(0.7, 0.0001)


func test_take_hands_state_over_exactly_once() -> void:
	# Two players in the next scene must not both pick up the same music position.
	_state.put({"section": "explore"})
	assert_dict(_state.take()).is_not_empty()
	assert_dict(_state.take()).is_empty()
	assert_bool(_state.has_state).is_false()


func test_peek_does_not_consume() -> void:
	_state.put({"section": "explore"})
	assert_dict(_state.peek()).is_not_empty()
	assert_bool(_state.has_state).is_true()
	assert_dict(_state.take()).is_not_empty()


func test_putting_an_empty_dictionary_clears_what_was_there() -> void:
	# A player that stopped before the scene change must not leave stale music behind for the
	# next scene to restore.
	_state.put({"section": "combat"})
	_state.put({})
	assert_bool(_state.has_state).is_false()


func test_clear_throws_it_away() -> void:
	_state.put({"section": "combat"})
	_state.clear()
	assert_bool(_state.has_state).is_false()


func test_stored_state_is_a_copy() -> void:
	# The caller keeps writing to its own dictionary after the scene change is scheduled.
	var mine := {"section": "explore", "clock": {"position": 1.0}}
	_state.put(mine)
	mine["section"] = "combat"
	mine["clock"]["position"] = 99.0
	var out: Dictionary = _state.take()
	assert_str(out["section"]).is_equal("explore")
	assert_float(out["clock"]["position"]).is_equal_approx(1.0, 0.0001)


func test_state_stored_is_emitted_for_a_save_system() -> void:
	var seen: Array[Dictionary] = []
	_state.state_stored.connect(func(s: Dictionary) -> void: seen.append(s))
	_state.put({"section": "combat"})
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0]["section"]).is_equal("combat")
