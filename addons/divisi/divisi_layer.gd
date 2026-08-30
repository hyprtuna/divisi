class_name DivisiLayer
extends Resource

## One vertical layer of a [DivisiSection]: a stem, and how loud it is at a given intensity.
##
## The stem itself is mixed by the engine, never by divisi. See [DivisiSection].

## Shown in the [DivisiDebug] overlay and in the inspector's array entry. Not used for lookup.
@export var layer_name: StringName = &""

## The stem. Every layer of a section must be the same length and tempo: the engine starts all
## of a synchronized stream's sub playbacks at the same position
## ([code]audio_stream_synchronized.cpp:196[/code] at 4.4-stable,
## [code]:197[/code] at 4.7.2-stable), so layers of different lengths drift apart at the first
## loop point.
@export var stream: AudioStream = null

## Amplitude of this layer, from 0 on the left to 1 on the right, as
## [member DivisiPlayer.intensity] sweeps from 0 to 1. The value is a linear amplitude
## multiplier applied under [member max_db], so 1.0 means [member max_db] and 0.5 means about
## 6 dB below it.
##
## Leave it null, or make it a flat line, for a layer that intensity should not touch: set its
## level with [member max_db] and it stays there.
@export var gain: Curve = null

## Level of this layer when [member gain] reads 1.0.
@export_range(-60.0, 12.0, 0.01, "suffix:dB") var max_db: float = 0.0


## Level in dB for this layer at [param intensity], to hand to
## [method AudioStreamSynchronized.set_sync_stream_volume].
func gain_db(intensity: float) -> float:
	var amount := 1.0
	if gain != null:
		amount = clampf(gain.sample(clampf(intensity, 0.0, 1.0)), 0.0, 1.0)
	if amount <= 0.0:
		return DivisiClock.SILENCE_DB
	return maxf(DivisiClock.SILENCE_DB, max_db + linear_to_db(amount))
