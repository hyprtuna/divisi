extends GdUnitTestSuite

## What the on screen readout actually says.
##
## The overlay is the artefact the README screenshots, so a wrong number in it is a wrong
## number everybody sees. These read the text off the [RichTextLabel] the overlay draws into,
## rather than calling the formatter, because the rendered line is the thing that was wrong.

const EXPLORE := preload("res://demo/sections/explore.tres")

var _player: DivisiPlayer
var _debug: DivisiDebug


func before_test() -> void:
	_player = auto_free(DivisiPlayer.new())
	_player.sections = [EXPLORE] as Array[DivisiSection]
	add_child(_player)
	_debug = auto_free(DivisiDebug.new())
	_debug.player = _player
	add_child(_debug)


func after_test() -> void:
	_player.stop()


func _rendered() -> String:
	for panel in _debug.get_children():
		for child in panel.get_children():
			if child is RichTextLabel:
				return child.text
	return ""


# Plays, sets the meter, and lets the overlay draw a frame with it.
func _readout_in(beats_per_bar: int) -> String:
	_player.play(&"explore")
	_player.clock.beats_per_bar = beats_per_bar
	await get_tree().process_frame
	await get_tree().process_frame
	return _rendered()


func test_a_bar_of_three_is_not_rendered_as_three_over_three() -> void:
	# The line passed beats_per_bar as both the numerator and the denominator of a time
	# signature, so 3/4 came out as "3/3". A DivisiClock carries no note value, so the
	# denominator was never knowable and there was nothing to print in its place.
	var text: String = await _readout_in(3)
	assert_str(text).contains("3 beats/bar")
	assert_str(text).not_contains("3/3")


func test_a_bar_of_four_says_how_many_beats_are_in_it() -> void:
	# 4/4 was the one meter the old line got right, which is why it shipped.
	var text: String = await _readout_in(4)
	assert_str(text).contains("4 beats/bar")
	assert_str(text).not_contains("4/4")


func test_a_bar_of_seven_is_not_rendered_as_seven_over_seven() -> void:
	var text: String = await _readout_in(7)
	assert_str(text).contains("7 beats/bar")
	assert_str(text).not_contains("7/7")


func test_a_bar_of_one_beat_is_not_called_beats() -> void:
	var text: String = await _readout_in(1)
	assert_str(text).contains("1 beat/bar")


func test_the_readout_carries_the_section_and_the_tempo() -> void:
	# The meter sits on the bar:beat line, so the rest of that line has to survive the change.
	var text: String = await _readout_in(4)
	assert_str(text).contains("section    explore")
	assert_str(text).contains("120.0 BPM")
	assert_str(text).contains("bar:beat")
