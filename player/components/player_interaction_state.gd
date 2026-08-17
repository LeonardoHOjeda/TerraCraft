class_name PlayerInteractionState
extends Node

signal inventory_open_changed(is_open: bool)

var _inventory_open: bool = false


func set_inventory_open(is_open: bool) -> void:
	if _inventory_open == is_open:
		return
	_inventory_open = is_open
	inventory_open_changed.emit(_inventory_open)


func is_inventory_open() -> bool:
	return _inventory_open


func can_interact_with_blocks() -> bool:
	return not _inventory_open
