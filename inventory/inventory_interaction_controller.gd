class_name InventoryInteractionController
extends RefCounted

var inventory: Inventory
var cursor_item: int = ItemRegistry.Item.NONE
var cursor_amount: int = 0
var cursor_origin_index: int = -1


func setup(new_inventory: Inventory) -> void:
	inventory = new_inventory


func handle_left_click(index: int) -> void:
	var slot_item := inventory.get_item(index)
	var slot_amount := inventory.get_amount(index)

	if cursor_item == ItemRegistry.Item.NONE:
		if slot_item == ItemRegistry.Item.NONE:
			return
		cursor_item = slot_item
		cursor_amount = slot_amount
		cursor_origin_index = index
		inventory.set_slot(index, ItemRegistry.Item.NONE, 0)
		return

	if slot_item == ItemRegistry.Item.NONE:
		inventory.set_slot(index, cursor_item, cursor_amount)
		clear_cursor()
		return

	if slot_item == cursor_item:
		cursor_amount = inventory.add_to_slot(index, cursor_item, cursor_amount)
		if cursor_amount <= 0:
			clear_cursor()
		return

	inventory.set_slot(index, cursor_item, cursor_amount)
	cursor_item = slot_item
	cursor_amount = slot_amount
	cursor_origin_index = index


func handle_right_click(index: int) -> void:
	var slot_item := inventory.get_item(index)
	var slot_amount := inventory.get_amount(index)

	if cursor_item == ItemRegistry.Item.NONE:
		if slot_item == ItemRegistry.Item.NONE:
			return
		var take_amount := ceili(slot_amount / 2.0)
		cursor_item = slot_item
		cursor_amount = take_amount
		cursor_origin_index = index
		inventory.remove_item(index, take_amount)
		return

	if slot_item == ItemRegistry.Item.NONE:
		inventory.set_slot(index, cursor_item, 1)
		cursor_amount -= 1
		if cursor_amount <= 0:
			clear_cursor()
		return

	if slot_item == cursor_item:
		var remaining := inventory.add_to_slot(index, cursor_item, 1)
		if remaining == 0:
			cursor_amount -= 1
			if cursor_amount <= 0:
				clear_cursor()


func handle_shift_click(index: int) -> void:
	if cursor_item != ItemRegistry.Item.NONE:
		return
	if inventory.get_item(index) == ItemRegistry.Item.NONE:
		return

	if index < Inventory.HOTBAR_START:
		inventory.move_stack_to_range(index, Inventory.HOTBAR_START, Inventory.TOTAL_SLOT_COUNT)
	else:
		inventory.move_stack_to_range(index, 0, Inventory.HOTBAR_START)


func handle_double_click(index: int) -> void:
	var target_item := cursor_item

	if target_item == ItemRegistry.Item.NONE:
		target_item = inventory.get_item(index)
		if target_item == ItemRegistry.Item.NONE:
			return
		cursor_item = target_item
		cursor_amount = 0
		cursor_origin_index = index

	var max_stack := ItemRegistry.get_max_stack(target_item)

	for i in Inventory.TOTAL_SLOT_COUNT:
		if cursor_amount >= max_stack:
			break
		if inventory.get_item(i) != target_item:
			continue
		var available := inventory.get_amount(i)
		var needed := max_stack - cursor_amount
		var to_take: int = min(available, needed)
		if to_take <= 0:
			continue
		inventory.remove_item(i, to_take)
		cursor_amount += to_take


func return_cursor_to_inventory() -> bool:
	if cursor_item == ItemRegistry.Item.NONE or cursor_amount <= 0:
		clear_cursor()
		return true

	var remaining := cursor_amount

	if cursor_origin_index >= 0 and cursor_origin_index < Inventory.TOTAL_SLOT_COUNT:
		var origin_item := inventory.get_item(cursor_origin_index)
		if origin_item == ItemRegistry.Item.NONE or origin_item == cursor_item:
			remaining = inventory.add_to_slot(
				cursor_origin_index,
				cursor_item,
				remaining
			)

	if remaining > 0:
		remaining = inventory.add_item(cursor_item, remaining)

	cursor_amount = remaining
	if cursor_amount <= 0:
		clear_cursor()
		return true

	return false


func clear_cursor() -> void:
	cursor_item = ItemRegistry.Item.NONE
	cursor_amount = 0
	cursor_origin_index = -1
