class_name GameplayBootstrap
extends Node3D

const AUTOSAVE_INTERVAL_SECONDS := 45.0
const SPAWN_READY_TIMEOUT_SECONDS := 30.0
const SPAWN_RECOVERY_HEIGHT := 16

var bootstrap_error := ""
var loaded_player_state: Dictionary = {}
var spawn_wait_elapsed := 0.0
var waiting_for_spawn := false


func _enter_tree() -> void:
	var metadata := WorldManager.get_active_world_metadata()
	var validation_error := _validate_active_world(metadata)
	if not validation_error.is_empty():
		_abort_bootstrap(validation_error)
		return

	var world := get_node_or_null("World") as World
	var player := get_node_or_null("Player") as Player
	if world == null:
		_abort_bootstrap("Gameplay cannot start because its World node is missing.")
		return
	if player == null:
		_abort_bootstrap("Gameplay cannot start because its Player node is missing.")
		return
	loaded_player_state = WorldManager.get_active_player_state()
	player.apply_saved_transform(loaded_player_state)
	var loaded_data := WorldManager.get_active_world_chunk_data()
	var configure_error := world.configure(
		int(metadata["seed"]),
		loaded_data.get("overrides", {}),
		loaded_data.get("special", {})
	)
	if configure_error != OK:
		_abort_bootstrap("Gameplay could not configure World before generation started.")


func _ready() -> void:
	if not bootstrap_error.is_empty():
		_show_bootstrap_error()
		return
	var player := get_node("Player") as Player
	player.import_state(loaded_player_state)
	player.begin_spawn_wait()
	waiting_for_spawn = true
	set_process(true)
	var autosave_timer := Timer.new()
	autosave_timer.name = "WorldAutosaveTimer"
	autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(save_world_changes)
	add_child(autosave_timer)


func _process(delta: float) -> void:
	if not waiting_for_spawn:
		return
	var world := get_node_or_null("World") as World
	var player := get_node_or_null("Player") as Player
	if world == null or player == null:
		waiting_for_spawn = false
		return
	if world.is_chunk_collision_ready_for_world_position(player.global_position):
		if _recover_player_vertical_space(player):
			player.finish_spawn_wait()
		else:
			push_error("Player remains disabled because no safe vertical recovery position was found.")
		waiting_for_spawn = false
		return
	spawn_wait_elapsed += delta
	if spawn_wait_elapsed >= SPAWN_READY_TIMEOUT_SECONDS:
		waiting_for_spawn = false
		push_error("Player spawn timed out while waiting for the central chunk collider; the player remains disabled.")


func _recover_player_vertical_space(player: Player) -> bool:
	if player.is_body_space_free():
		return true
	var saved_position := player.global_position
	for offset in range(1, SPAWN_RECOVERY_HEIGHT + 1):
		player.global_position = saved_position + Vector3.UP * offset
		if player.is_body_space_free():
			return true
	player.global_position = saved_position
	push_warning("No free vertical recovery position was found near the saved player position.")
	return false


func save_world_changes() -> Dictionary:
	var world := get_node_or_null("World") as World
	var player := get_node_or_null("Player") as Player
	if world == null or player == null:
		return {"ok": false, "error": "Gameplay World or Player node is unavailable."}
	return WorldManager.save_active_world_changes(world, player)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and bootstrap_error.is_empty():
		var result := save_world_changes()
		if not result.get("ok", false):
			push_error("Could not save active world changes during shutdown: %s" % result.get("error", "Unknown error"))


func _validate_active_world(metadata: Dictionary) -> String:
	if WorldManager.active_world_id.is_empty() or metadata.is_empty():
		return "Gameplay cannot start without an active world."
	if metadata.get("id", "") != WorldManager.active_world_id:
		return "Gameplay cannot start because the active world metadata is inconsistent."
	if not metadata.has("seed") or not metadata["seed"] is int:
		return "Gameplay cannot start because the active world seed is invalid."
	return ""


func _abort_bootstrap(message: String) -> void:
	bootstrap_error = message
	push_error(message)
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _show_bootstrap_error() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BootstrapErrorLayer"
	add_child(layer)
	var label := Label.new()
	label.name = "BootstrapError"
	label.text = bootstrap_error
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
