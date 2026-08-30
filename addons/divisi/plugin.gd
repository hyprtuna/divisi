@tool
extends EditorPlugin

## Registers the DivisiState autoload. Everything else in divisi is a global class, which
## Godot picks up from the scripts themselves without a plugin.
##
## The autoload is a small Node that holds one Dictionary. It is inert unless a
## [DivisiPlayer] has persist_across_scenes set, or you call into it yourself, so leaving it
## enabled costs a node and nothing else. Remove it under Project Settings, Globals if you
## would rather not have it.

const AUTOLOAD_NAME := "DivisiState"
const AUTOLOAD_PATH := "res://addons/divisi/divisi_state.gd"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
