extends Node

## Drives the divisi demo. Both demo scenes use this same script; they differ only in the
## title and in which scene the "change scene" button loads.
##
## The UI is built in code rather than laid out in the scene so that the whole demo is
## readable top to bottom in one file. The two things that matter are in the scene itself: a
## DivisiPlayer holding the two sections, and a DivisiDebug drawing the readout.

## Shown at the top, so that a scene change is visibly a scene change.
@export var scene_title: String = "Scene"

## The scene the change button loads.
@export_file("*.tscn") var next_scene: String = ""

## What the stinger button fires.
@export var stinger: AudioStream = null

var _player: DivisiPlayer = null
var _pulse: float = 0.0
var _pulse_is_downbeat: bool = false
var _quantize: DivisiQuantize.Mode = DivisiQuantize.NEXT_BAR

var _beat_light: Panel = null
var _threat: HSlider = null
var _threat_value: Label = null
var _section_button: Button = null
var _status: Label = null


func _ready() -> void:
	for child in get_children():
		if child is DivisiPlayer:
			_player = child
	if _player == null:
		push_error("demo: this scene has no DivisiPlayer.")
		return
	_player.beat.connect(_on_beat)
	_player.transition_started.connect(_on_transition_started)
	_player.section_changed.connect(_on_section_changed)
	_build_ui()
	_threat.value = _player.intensity
	_refresh_section_button()


func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 4.0)
	if _beat_light != null:
		var lit := Color(0.42, 0.88, 0.54) if _pulse_is_downbeat else Color(0.56, 0.72, 1.0)
		var dark := Color(0.13, 0.14, 0.18)
		_beat_light.modulate = dark.lerp(lit, _pulse)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	layer.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = scene_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# 1. The threat slider: one value, four layers.
	var threat_row := HBoxContainer.new()
	threat_row.add_theme_constant_override("separation", 12)
	column.add_child(threat_row)
	var threat_label := Label.new()
	threat_label.text = "threat"
	threat_label.custom_minimum_size = Vector2(70, 0)
	threat_row.add_child(threat_label)
	_threat = HSlider.new()
	_threat.min_value = 0.0
	_threat.max_value = 1.0
	_threat.step = 0.001
	_threat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_threat.value_changed.connect(_on_threat_changed)
	threat_row.add_child(_threat)
	_threat_value = Label.new()
	_threat_value.custom_minimum_size = Vector2(56, 0)
	_threat_value.text = "0.000"
	threat_row.add_child(_threat_value)

	# 3. The beat light, pulsed from the beat signal.
	var beat_row := HBoxContainer.new()
	beat_row.add_theme_constant_override("separation", 12)
	column.add_child(beat_row)
	var beat_label := Label.new()
	beat_label.text = "beat"
	beat_label.custom_minimum_size = Vector2(70, 0)
	beat_row.add_child(beat_label)
	_beat_light = Panel.new()
	_beat_light.custom_minimum_size = Vector2(0, 26)
	_beat_light.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	beat_row.add_child(_beat_light)

	# 2 and 4. Transition, quantization and stinger.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	_section_button = Button.new()
	_section_button.pressed.connect(_on_transition_pressed)
	buttons.add_child(_section_button)

	var quantize_menu := OptionButton.new()
	quantize_menu.add_item("on the next bar", DivisiQuantize.NEXT_BAR)
	quantize_menu.add_item("on the next beat", DivisiQuantize.NEXT_BEAT)
	quantize_menu.add_item("right now", DivisiQuantize.NOW)
	quantize_menu.item_selected.connect(_on_quantize_selected.bind(quantize_menu))
	buttons.add_child(quantize_menu)

	var stinger_button := Button.new()
	stinger_button.text = "stinger on the next beat"
	stinger_button.pressed.connect(_on_stinger_pressed)
	stinger_button.disabled = stinger == null
	buttons.add_child(stinger_button)

	# 5. The scene change, with the music carrying on.
	var scene_button := Button.new()
	scene_button.text = "change scene, keep the music"
	scene_button.pressed.connect(_on_change_scene_pressed)
	scene_button.disabled = next_scene.is_empty()
	buttons.add_child(scene_button)

	_status = Label.new()
	_status.text = "watch the drift counter in the corner."
	column.add_child(_status)


func _refresh_section_button() -> void:
	_section_button.text = "go to %s" % _other_section()


func _other_section() -> StringName:
	if _player.current_section != null and _player.current_section.section_name == &"explore":
		return &"combat"
	return &"explore"


func _on_threat_changed(value: float) -> void:
	_player.intensity = value
	_threat_value.text = "%.3f" % value


func _on_transition_pressed() -> void:
	_player.transition_to(_other_section(), _quantize)


func _on_quantize_selected(index: int, menu: OptionButton) -> void:
	_quantize = menu.get_item_id(index) as DivisiQuantize.Mode


func _on_stinger_pressed() -> void:
	_player.play_stinger(stinger, DivisiQuantize.NEXT_BEAT, -4.0)


func _on_change_scene_pressed() -> void:
	get_tree().change_scene_to_file(next_scene)


func _on_beat(index: int) -> void:
	_pulse = 1.0
	_pulse_is_downbeat = _player.clock.beat_in_bar == 0
	if index % 4 == 0:
		_refresh_section_button()


func _on_transition_started(from_section: StringName, to: StringName, at_bar: int) -> void:
	_status.text = "%s to %s, landing on bar %d" % [from_section, to, at_bar]


func _on_section_changed(section_name: StringName) -> void:
	_status.text = "playing %s" % section_name
	_refresh_section_button()
