extends GdUnitTestSuite

## How a section becomes the AudioStreamSynchronized the engine mixes.

const EPS := 0.001


func _stream(seconds: float) -> AudioStreamWAV:
	# A silent 16 bit mono buffer. Nothing plays it here; it exists so that get_length() and
	# the stream slots have something real in them.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	# Built here and then assigned. Reading wav.data hands back a copy, so resizing it in
	# place would grow a temporary and leave the stream zero length.
	var buffer := PackedByteArray()
	buffer.resize(int(44100.0 * seconds) * 2)
	wav.data = buffer
	return wav


func _layer(max_db: float, stream: AudioStream) -> DivisiLayer:
	var layer := DivisiLayer.new()
	layer.max_db = max_db
	layer.stream = stream
	return layer


func _ramp() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


func _section(layers: Array[DivisiLayer]) -> DivisiSection:
	var section := DivisiSection.new()
	section.section_name = &"test"
	section.bpm = 120.0
	section.beats_per_bar = 4
	section.layers = layers
	return section


func test_loop_length_comes_from_the_first_layer_with_a_stream() -> void:
	var section := _section([_layer(0.0, null), _layer(0.0, _stream(16.0))] as Array[DivisiLayer])
	assert_float(section.loop_length()).is_equal_approx(16.0, 0.01)


func test_loop_length_of_an_empty_section_is_zero() -> void:
	var section := _section([] as Array[DivisiLayer])
	assert_float(section.loop_length()).is_equal_approx(0.0, EPS)


func test_layers_without_a_stream_are_not_mixed() -> void:
	# A half filled inspector array should not push a null into a stream slot.
	var good := _layer(0.0, _stream(1.0))
	var section := _section([_layer(0.0, null), good, null] as Array[DivisiLayer])
	var mixed := section.mixed_layers()
	assert_int(mixed.size()).is_equal(1)
	assert_object(mixed[0]).is_same(good)


func test_build_stream_fills_one_slot_per_mixed_layer() -> void:
	var section := _section(
		[_layer(0.0, _stream(1.0)), _layer(-6.0, _stream(1.0))] as Array[DivisiLayer]
	)
	var sync := section.build_stream(1.0)
	assert_int(sync.stream_count).is_equal(2)
	assert_object(sync.get_sync_stream(0)).is_not_null()
	assert_object(sync.get_sync_stream(1)).is_not_null()


func test_build_stream_writes_the_gain_for_the_given_intensity() -> void:
	var layer := _layer(0.0, _stream(1.0))
	layer.gain = _ramp()
	var section := _section([layer] as Array[DivisiLayer])

	var loud := section.build_stream(1.0)
	assert_float(loud.get_sync_stream_volume(0)).is_equal_approx(0.0, EPS)
	var silent := section.build_stream(0.0)
	assert_float(silent.get_sync_stream_volume(0)).is_equal_approx(DivisiClock.SILENCE_DB, EPS)


func test_every_call_returns_a_fresh_stream() -> void:
	# The engine keeps per layer volume on the resource, not on the playback
	# (audio_stream_synchronized.h:51 at 4.4-stable). Two players sharing one instance would
	# share its gains, so the outgoing side of a crossfade would follow the incoming side's
	# intensity. This test is the one that catches a well meant cache.
	var fading := _layer(0.0, _stream(1.0))
	fading.gain = _ramp()
	var section := _section([fading] as Array[DivisiLayer])
	var first := section.build_stream(1.0)
	var second := section.build_stream(0.0)
	assert_object(first).is_not_same(second)
	assert_float(first.get_sync_stream_volume(0)).is_equal_approx(0.0, EPS)
	assert_float(second.get_sync_stream_volume(0)).is_equal_approx(DivisiClock.SILENCE_DB, EPS)


func test_more_layers_than_the_engine_mixes_are_dropped_not_wrapped() -> void:
	var layers: Array[DivisiLayer] = []
	for i in AudioStreamSynchronized.MAX_STREAMS + 5:
		layers.append(_layer(0.0, _stream(1.0)))
	var section := _section(layers)
	assert_int(section.mixed_layers().size()).is_equal(AudioStreamSynchronized.MAX_STREAMS)
	assert_int(section.build_stream(1.0).stream_count).is_equal(AudioStreamSynchronized.MAX_STREAMS)
