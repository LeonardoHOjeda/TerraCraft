class_name CraftingStation
extends Area3D

@export var station_type: CraftingRegistry.Station = CraftingRegistry.Station.WORKBENCH


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.add_nearby_station(station_type)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.remove_nearby_station(station_type)