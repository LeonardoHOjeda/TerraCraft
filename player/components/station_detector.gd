class_name StationDetector
extends Node

signal stations_changed

var player: Player
var world: World
var station_radius: int
var check_interval: float
var check_timer := 0.0
var nearby_workbench := false
var nearby_furnace := false

func setup(new_player: Player, new_world: World, radius: int, interval: float) -> void:
	player = new_player
	world = new_world
	station_radius = radius
	check_interval = interval

func process(delta: float) -> void:
	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		update_nearby_crafting_stations()

func has_nearby_station(station: int) -> bool:
	match station:
		CraftingRegistry.Station.NONE:
			return true
		CraftingRegistry.Station.WORKBENCH:
			return nearby_workbench
		CraftingRegistry.Station.FURNACE:
			return nearby_furnace
	return false

func update_nearby_crafting_stations() -> void:
	if world == null:
		return
	var found_workbench := false
	var found_furnace := false
	var player_block := Vector3i(floor(player.global_position.x), floor(player.global_position.y), floor(player.global_position.z))
	for x in range(-station_radius, station_radius + 1):
		for y in range(-station_radius, station_radius + 1):
			for z in range(-station_radius, station_radius + 1):
				var block := world.get_block_at_world_position(player_block + Vector3i(x, y, z))
				if block == BlockRegistry.Block.WORKBENCH:
					found_workbench = true
				if block == BlockRegistry.Block.FURNACE:
					found_furnace = true
			if found_workbench and found_furnace:
				break
		if found_workbench and found_furnace:
			break
	var changed := nearby_workbench != found_workbench or nearby_furnace != found_furnace
	nearby_workbench = found_workbench
	nearby_furnace = found_furnace
	if changed:
		stations_changed.emit()
