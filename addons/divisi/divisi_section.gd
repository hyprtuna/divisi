class_name DivisiSection
extends Resource

## A named piece of music: a tempo, a time signature and the layers that make it up.
##
## At runtime a section plays as one [AudioStreamSynchronized]. The engine does the mixing.
## It reads each layer's volume out of the resource on every mix chunk
## ([code]audio_stream_synchronized.cpp:231[/code] at 4.4-stable, [code]:232[/code] at
## 4.7.2-stable), so a volume written from script takes effect on the next chunk, and it
## starts every sub playback at the same position ([code]:196[/code] and [code]:197[/code]),
## so the layers are phase locked by the engine rather than by divisi.

## The name [method DivisiPlayer.transition_to] looks this section up by. Must be unique
## within a [member DivisiPlayer.sections] array.
@export var section_name: StringName = &""

## Tempo of every layer in this section.
@export_range(1.0, 400.0, 0.01, "or_greater", "suffix:BPM") var bpm: float = 120.0

## Beats in a bar. 4 is 4/4.
@export_range(1, 32, 1, "or_greater") var beats_per_bar: int = 4

## The stems, mixed together. At most [constant AudioStreamSynchronized.MAX_STREAMS] of them.
@export var layers: Array[DivisiLayer] = []


## Length of one loop of this section in seconds, taken from the first layer that has a
## stream. 0.0 when the section has no usable layer, and 0.0 when that stream is not set to
## loop: a stream that runs out is not a loop, and telling the clock otherwise makes it wait
## forever for a wrap that never comes.
##
## [method AudioStream.has_loop] is only on the concrete stream types, not on [AudioStream]
## itself, so it is called through [method Object.has_method]. Checked on 4.4.1 and 4.7.2:
## present on [AudioStreamOggVorbis] and [AudioStreamWAV], absent on [AudioStreamSynchronized].
func loop_length() -> float:
	var mixed := mixed_layers()
	if mixed.is_empty():
		return 0.0
	var stream := mixed[0].stream
	if stream.has_method("has_loop") and not stream.has_loop():
		return 0.0
	return stream.get_length()


## Whether this section's stems loop. A section that does not loop plays once and stops.
func loops() -> bool:
	return loop_length() > 0.0


## Builds a fresh [AudioStreamSynchronized] holding every layer, with each layer's volume set
## for [param intensity].
##
## Fresh on every call, and that is the point. A synchronized stream keeps its per layer
## volumes on the [Resource] itself ([code]audio_stream_synchronized.h:51[/code] at
## 4.4-stable, [code]:50[/code] at 4.7.2-stable), not on the playback, so two players sharing
## one instance also share its layer gains. During a crossfade divisi has two players running
## the same section's stems at once, and reusing one instance would make the outgoing mix
## follow the incoming one's intensity.
func build_stream(intensity: float) -> AudioStreamSynchronized:
	var sync := AudioStreamSynchronized.new()
	var mixed := mixed_layers()
	sync.stream_count = mixed.size()
	for i in mixed.size():
		sync.set_sync_stream(i, mixed[i].stream)
		sync.set_sync_stream_volume(i, mixed[i].gain_db(intensity))
	return sync


## The layers that [method build_stream] actually mixes, in the order it gives them to the
## engine. Layers with no stream are skipped, so this is not always [member layers].
func mixed_layers() -> Array[DivisiLayer]:
	var usable: Array[DivisiLayer] = []
	for layer in layers:
		if layer != null and layer.stream != null:
			usable.append(layer)
	if usable.size() > AudioStreamSynchronized.MAX_STREAMS:
		push_warning(
			(
				"divisi: section '%s' has %d usable layers, the engine mixes at most %d."
				% [section_name, usable.size(), AudioStreamSynchronized.MAX_STREAMS]
			)
		)
		usable.resize(AudioStreamSynchronized.MAX_STREAMS)
	return usable
