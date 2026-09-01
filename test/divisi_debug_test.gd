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


# The panel and the label the overlay builds in _ready(), in that order.
func _panel_and_label() -> Array:
	for panel in _debug.get_children():
		for child in panel.get_children():
			if child is RichTextLabel:
				return [panel, child]
	return []


# Pins the clock at one reading and lets the overlay draw a frame with it. The player ticks
# the clock every frame, so both have to stop processing or the fields move back to real time
# before the overlay reads them. The overlay itself keeps processing: it is what is measured.
func _rendered_at(bar: int, beats_per_bar: int, bpm: float, font_size: int = 0) -> Array:
	_player.play(&"explore")
	_player.set_process(false)
	_player.clock.set_process(false)
	_player.clock.bpm = bpm
	_player.clock.beats_per_bar = beats_per_bar
	_player.clock.bar_index = bar
	_player.clock.beat_in_bar = 0
	var parts := _panel_and_label()
	if font_size > 0:
		var theme := Theme.new()
		theme.default_font_size = font_size
		parts[0].theme = theme
	await get_tree().process_frame
	await get_tree().process_frame
	return parts


# Rendered lines beyond the ones the text actually asks for. Zero means nothing wrapped.
func _overflow_lines(label: RichTextLabel) -> int:
	return label.get_line_count() - (label.text.count("\n") + 1)


func test_the_readout_does_not_wrap_at_the_widest_reading_it_can_show() -> void:
	# The label was pinned at 300 px wide while the demo's own line measures 295 px, so one
	# more character anywhere wrapped it: bar 10 arrives 20 seconds into the demo.
	var parts: Array = await _rendered_at(100, 10, 1000.0)
	assert_int(_overflow_lines(parts[1])).is_equal(0)


func test_the_readout_does_not_wrap_under_a_larger_theme_font() -> void:
	# A game that sets default_font_size 17 or more wrapped the line at every reading, with
	# no wide number needed.
	var parts: Array = await _rendered_at(7, 4, 120.0, 18)
	assert_int(_overflow_lines(parts[1])).is_equal(0)


func test_the_panel_widens_to_fit_a_wider_readout() -> void:
	# Sizing to content is the fix; a fixed minimum large enough for today's demo is not,
	# because the next wider reading walks straight back into the wrap.
	var narrow: Array = await _rendered_at(7, 4, 120.0)
	var narrow_width: float = narrow[0].size.x
	var wide: Array = await _rendered_at(100, 10, 1000.0)
	assert_float(wide[0].size.x).is_greater(narrow_width)
