class_name DivisiQuantize
extends RefCounted

## Musical boundaries that divisi can schedule against.
##
## Passed to [method DivisiPlayer.transition_to], [method DivisiPlayer.play_stinger]
## and [method DivisiClock.time_to_next]. The plain constants exist so calling code
## reads as [code]DivisiQuantize.NEXT_BAR[/code]; [enum Mode] is the same set, for
## [code]@export[/code] properties that want an inspector dropdown.

enum Mode {
	NOW = 0,  ## As soon as possible, on the next processed frame. Breaks the grid on purpose.
	NEXT_BEAT = 1,  ## The next beat boundary.
	NEXT_BAR = 2,  ## The next bar boundary, that is, the next downbeat.
}

const NOW := Mode.NOW
const NEXT_BEAT := Mode.NEXT_BEAT
const NEXT_BAR := Mode.NEXT_BAR
