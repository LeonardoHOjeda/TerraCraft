class_name Inventory
extends Node

signal slot_changed(index: int)

const INVENTORY_SLOT_COUNT := 27
const HOTBAR_SLOT_COUNT := 9
const TOTAL_SLOT_COUNT := 36
const HOTBAR_START := 27

var items: Array[int] = []
var amounts: Array[int] = []


func _ready() -> void:
	items.resize(TOTAL_SLOT_COUNT)
	amounts.resize(TOTAL_SLOT_COUNT)

	for i in TOTAL_SLOT_COUNT:
		items[i] = ItemRegistry.Item.NONE
		amounts[i] = 0


func get_item(index: int) -> int:
	if index < 0 or index >= TOTAL_SLOT_COUNT:
		return ItemRegistry.Item.NONE

	return items[index]


func get_amount(index: int) -> int:
	if index < 0 or index >= TOTAL_SLOT_COUNT:
		return 0

	return amounts[index]


func add_item(
	item_id: int,
	amount: int = 1
) -> int:
	if (
		item_id == ItemRegistry.Item.NONE
		or amount <= 0
	):
		return amount

	var remaining := amount
	var max_stack := (
		ItemRegistry.get_max_stack(item_id)
	)

	# Completar stacks existentes.
	for i in TOTAL_SLOT_COUNT:
		if items[i] != item_id:
			continue

		if amounts[i] >= max_stack:
			continue

		var available := (
			max_stack - amounts[i]
		)

		var to_add = min(available,remaining)

		amounts[i] += to_add
		remaining -= to_add

		slot_changed.emit(i)

		if remaining <= 0:
			return 0

	# Primero llenar la hotbar.
	for i in range(
		HOTBAR_START,
		TOTAL_SLOT_COUNT
	):
		if items[i] != ItemRegistry.Item.NONE:
			continue

		var to_add = min(max_stack,remaining)

		items[i] = item_id
		amounts[i] = to_add
		remaining -= to_add

		slot_changed.emit(i)

		if remaining <= 0:
			return 0

	# Después llenar la mochila.
	for i in range(
		0,
		INVENTORY_SLOT_COUNT
	):
		if items[i] != ItemRegistry.Item.NONE:
			continue

		var to_add = min(max_stack,remaining)

		items[i] = item_id
		amounts[i] = to_add
		remaining -= to_add

		slot_changed.emit(i)

		if remaining <= 0:
			return 0

	return remaining


func remove_item(index: int, amount: int = 1) -> bool:
	if index < 0 or index >= TOTAL_SLOT_COUNT:
		return false

	if amounts[index] < amount:
		return false

	amounts[index] -= amount

	if amounts[index] <= 0:
		items[index] = ItemRegistry.Item.NONE
		amounts[index] = 0

	slot_changed.emit(index)

	return true

func set_slot(index: int, item_id: int, amount: int) -> void:
	if index < 0 or index >= TOTAL_SLOT_COUNT:
		return

	if amount <= 0 or item_id == ItemRegistry.Item.NONE:
		items[index] = ItemRegistry.Item.NONE
		amounts[index] = 0
	else:
		items[index] = item_id
		amounts[index] = amount

	slot_changed.emit(index)


func add_to_slot(index: int, item_id: int, amount: int) -> int:
	if index < 0 or index >= TOTAL_SLOT_COUNT:
		return amount

	if amount <= 0:
		return 0

	var max_stack := ItemRegistry.get_max_stack(item_id)

	if items[index] == ItemRegistry.Item.NONE:
		var to_add = min(amount, max_stack)

		items[index] = item_id
		amounts[index] = to_add

		slot_changed.emit(index)

		return amount - to_add

	if items[index] != item_id:
		return amount

	var available := max_stack - amounts[index]

	if available <= 0:
		return amount

	var to_add = min(amount, available)

	amounts[index] += to_add
	slot_changed.emit(index)

	return amount - to_add

func move_stack_to_range(source_index: int, target_start: int, target_end: int) -> void:
	var item_id := get_item(source_index)
	var remaining := get_amount(source_index)

	if item_id == ItemRegistry.Item.NONE or remaining <= 0:
		return

	# Primero completar stacks existentes.
	for i in range(target_start, target_end):
		if items[i] != item_id:
			continue

		var previous_remaining := remaining

		remaining = add_to_slot(
			i,
			item_id,
			remaining
		)

		var moved := previous_remaining - remaining

		if moved > 0:
			remove_item(source_index, moved)

		if remaining <= 0:
			return

	# Después buscar slots vacíos.
	for i in range(target_start, target_end):
		if items[i] != ItemRegistry.Item.NONE:
			continue

		var previous_remaining := remaining

		remaining = add_to_slot(
			i,
			item_id,
			remaining
		)

		var moved := previous_remaining - remaining

		if moved > 0:
			remove_item(source_index, moved)

		if remaining <= 0:
			return