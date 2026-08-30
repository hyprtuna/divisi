extends Node

## Carries music state across a scene change. Registered by the plugin as the autoload
## [code]DivisiState[/code].
##
## This script deliberately has no [code]class_name[/code]: a global class and an autoload
## singleton cannot share a name in Godot 4, and the autoload name is the one that has to be
## [code]DivisiState[/code] so that [code]/root/DivisiState[/code] resolves.
##
## It holds a plain [Dictionary] and nothing else. It does not touch the audio server, does
## not keep a reference to a player, and does not write to disk. A [DivisiPlayer] with
## [member DivisiPlayer.persist_across_scenes] set puts its state here as it leaves the tree
## and takes it back in the next scene. If you would rather drive it yourself, leave that flag
## off and call [method DivisiPlayer.capture_state] and
## [method DivisiPlayer.restore_state] where you want them.

## Emitted whenever state is stored, so a save system can pick it up.
signal state_stored(state: Dictionary)

## Whether there is state waiting to be restored.
var has_state: bool:
	get:
		return not _state.is_empty()

var _state: Dictionary = {}


## Stores state. An empty dictionary clears what was there rather than storing nothing over
## it, so a player that stopped before the scene change does not leave stale music state
## behind for the next scene to restore.
func put(state: Dictionary) -> void:
	_state = state.duplicate(true)
	state_stored.emit(_state)


## Returns the stored state and clears it. One save is restored once: two players in the next
## scene must not both pick up the same music position.
func take() -> Dictionary:
	var out := _state
	_state = {}
	return out


## Returns the stored state without clearing it.
func peek() -> Dictionary:
	return _state.duplicate(true)


## Throws the stored state away.
func clear() -> void:
	_state = {}
