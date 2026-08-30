class_name DivisiDebug
extends CanvasLayer

## On screen readout of a [DivisiPlayer]: section, bar and beat, per layer gains, and how far
## the audio device's clock and the system clock have run apart.
##
## Two lines are worth reading together. "bar:beat" comes off the audio device, so it is
## always exactly where the music is. "vs system clock" is
## [member DivisiClock.system_clock_offset_seconds], the gap between that and the wall clock a
## [code]_position += delta[/code] implementation would have counted instead. It is not
## divisi's error; it is the difference between the two answers, and how large it gets is a
## property of the sound hardware. The engine's own
## [url=https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html]audio sync
## tutorial[/url] warns that on many machines it grows and never comes back.

## The player to read. Leave it null to use the first [DivisiPlayer] found under this node's
## parent.
@export var player: DivisiPlayer = null

## Where in the viewport to draw, in pixels from the top left. Named for what it is
## rather than [code]offset[/code], which [CanvasLayer] already defines.
@export var screen_offset: Vector2 = Vector2(16, 16)

## Where the system clock readout turns from green to amber, in milliseconds. The default is a
## tenth of a beat at 120 BPM, which is roughly where a beat callback placed by the wrong
## clock stops being subtle.
@export var offset_warn_ms: float = 50.0

var _label: RichTextLabel = null
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 128
	_panel = PanelContainer.new()
	_panel.position = screen_offset
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(300, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)

	if player == null:
		player = _find_player()


func _process(_delta: float) -> void:
	if _label == null:
		return
	_label.text = _readout()


func _find_player() -> DivisiPlayer:
	var from := get_parent()
	if from == null:
		return null
	for child in from.get_children():
		if child is DivisiPlayer:
			return child
	return null


func _readout() -> String:
	if player == null:
		return "[b]divisi[/b]\nno DivisiPlayer"
	if not player.playing or player.clock == null:
		return "[b]divisi[/b]\nstopped"

	var clock := player.clock
	var lines := PackedStringArray()
	lines.append("[b]divisi[/b]")
	var section := "-"
	if player.current_section != null:
		section = String(player.current_section.section_name)
	lines.append("section    %s" % section)
	if player.pending_section != null:
		lines.append("next      %s" % String(player.pending_section.section_name))
	lines.append(
		(
			"bar:beat   %d:%d    %.1f BPM  %d/4"
			% [clock.bar_index, clock.beat_in_bar, clock.bpm, clock.beats_per_bar]
		)
	)
	lines.append("position   %s" % _timecode(clock.position))
	lines.append("intensity  %.3f" % player.intensity)

	var offset_ms := clock.system_clock_offset_seconds * 1000.0
	var colour := "ffc861" if absf(offset_ms) > offset_warn_ms else "7fe08a"
	lines.append("vs system  [color=#%s]%+.1f ms[/color]" % [colour, offset_ms])
	if clock.skipped_beats > 0:
		lines.append("skipped    [color=#ff6161]%d beats[/color]" % clock.skipped_beats)

	for gain in player.layer_gains():
		var db: float = gain["db"]
		var name_text := String(gain["name"])
		if name_text.is_empty():
			name_text = "layer"
		lines.append("  %-9s %s %+6.1f dB" % [name_text, _meter(db), db])
	return "\n".join(lines)


# A level as a short bar of blocks, so four layers moving together are readable at a glance.
static func _meter(db: float) -> String:
	var amount := 0.0 if db <= DivisiClock.SILENCE_DB else db_to_linear(db)
	var filled := clampi(roundi(amount * 10.0), 0, 10)
	return "%s%s" % ["#".repeat(filled), ".".repeat(10 - filled)]


static func _timecode(seconds: float) -> String:
	var total := maxf(0.0, seconds)
	return "%d:%05.2f" % [int(total / 60.0), fmod(total, 60.0)]
