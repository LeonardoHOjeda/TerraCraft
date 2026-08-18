class_name HotbarController
extends Node

signal selection_changed(index: int)
signal selected_item_changed(item_id: int)

var inventory: Inventory
var selected_slot: int = 0
var selected_item: int = ItemRegistry.Item.NONE


func setup(new_inventory: Inventory) -> void:
	inventory = new_inventory
	if inventory != null:
		inventory.slot_changed.connect(_on_inventory_slot_changed)
	selected_item = get_selected_item()


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(selected_slot - 1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(selected_slot + 1)

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: select_slot(0)
			KEY_2: select_slot(1)
			KEY_3: select_slot(2)
			KEY_4: select_slot(3)
			KEY_5: select_slot(4)
			KEY_6: select_slot(5)
			KEY_7: select_slot(6)
			KEY_8: select_slot(7)
			KEY_9: select_slot(8)


func select_slot(index: int) -> void:
	selected_slot = wrapi(index, 0, Inventory.HOTBAR_SLOT_COUNT)
	selection_changed.emit(selected_slot)
	_emit_selected_item_changed_if_needed()


func get_selected_item() -> int:
	if inventory == null:
		return ItemRegistry.Item.NONE
	return inventory.get_item(get_selected_inventory_index())


func get_selected_block() -> int:
	return ItemRegistry.get_placeable_block(get_selected_item())


func consume_selected_item(amount: int = 1) -> bool:
	if inventory == null:
		return false
	return inventory.remove_item(get_selected_inventory_index(), amount)


func get_selected_inventory_index() -> int:
	return Inventory.HOTBAR_START + selected_slot


func _on_inventory_slot_changed(index: int) -> void:
	if index == get_selected_inventory_index():
		_emit_selected_item_changed_if_needed()


func _emit_selected_item_changed_if_needed() -> void:
	var current_item := get_selected_item()
	if current_item == selected_item:
		return
	selected_item = current_item
	selected_item_changed.emit(selected_item)
