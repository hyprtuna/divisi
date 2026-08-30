extends GdUnitTestSuite

## How a layer turns one intensity value into the dB the engine mixes it at.

const EPS := 0.001


func _layer(max_db: float, curve: Curve = null) -> DivisiLayer:
	var layer := DivisiLayer.new()
	layer.max_db = max_db
	layer.gain = curve
	return layer


func _ramp() -> Curve:
	# A straight line from 0 at intensity 0 to 1 at intensity 1.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


func _flat(value: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, value))
	curve.add_point(Vector2(1.0, value))
	return curve


func test_a_layer_with_no_curve_sits_at_its_max() -> void:
	# Leaving the curve off is how you say "intensity does not touch this layer".
	var layer := _layer(-3.0)
	assert_float(layer.gain_db(0.0)).is_equal_approx(-3.0, EPS)
	assert_float(layer.gain_db(1.0)).is_equal_approx(-3.0, EPS)


func test_a_flat_curve_also_sits_still() -> void:
	var layer := _layer(0.0, _flat(1.0))
	assert_float(layer.gain_db(0.0)).is_equal_approx(0.0, EPS)
	assert_float(layer.gain_db(0.6)).is_equal_approx(0.0, EPS)


func test_a_curve_at_one_gives_max_db() -> void:
	var layer := _layer(-6.0, _ramp())
	assert_float(layer.gain_db(1.0)).is_equal_approx(-6.0, EPS)


func test_a_curve_value_is_a_linear_amplitude_under_max_db() -> void:
	# Half amplitude is about 6 dB down, and it is measured from max_db, not from zero.
	var layer := _layer(-6.0, _flat(0.5))
	assert_float(layer.gain_db(0.5)).is_equal_approx(-6.0 + linear_to_db(0.5), EPS)


func test_a_curve_at_zero_is_silence_not_minus_infinity() -> void:
	# linear_to_db(0) is -inf, which is not a number the mixer can use.
	var layer := _layer(0.0, _ramp())
	assert_float(layer.gain_db(0.0)).is_equal_approx(DivisiClock.SILENCE_DB, EPS)


func test_a_ramp_follows_intensity() -> void:
	var layer := _layer(0.0, _ramp())
	var quiet := layer.gain_db(0.25)
	var loud := layer.gain_db(0.75)
	assert_float(quiet).is_less(loud)
	assert_float(loud).is_less_equal(0.0)


func test_intensity_outside_zero_to_one_is_clamped() -> void:
	var layer := _layer(0.0, _ramp())
	assert_float(layer.gain_db(-5.0)).is_equal_approx(layer.gain_db(0.0), EPS)
	assert_float(layer.gain_db(9.0)).is_equal_approx(layer.gain_db(1.0), EPS)


func test_a_very_low_max_db_still_floors_at_silence() -> void:
	var layer := _layer(-60.0, _flat(0.01))
	assert_float(layer.gain_db(0.5)).is_equal_approx(DivisiClock.SILENCE_DB, EPS)


func test_a_curve_above_one_is_clamped_rather_than_boosting() -> void:
	# A curve can be dragged above 1 in the inspector. Letting that add gain on top of max_db
	# turns the level the author set into a suggestion.
	var layer := _layer(-6.0, _flat(4.0))
	assert_float(layer.gain_db(0.5)).is_equal_approx(-6.0, EPS)
