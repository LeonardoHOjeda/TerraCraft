class_name GameplayBootstrap
extends Node3D

const AUTOSAVE_INTERVAL_SECONDS := 45.0

var bootstrap_error := ""


func _enter_tree() -> void:
	var metadata := WorldManager.get_active_world_metadata()
	var validation_error := _validate_active_world(metadata)
	if not validation_error.is_empty():
		_abort_bootstrap(validation_error)
		return

	var world := get_node_or_null("World") as World
	if world == null:
		_abort_bootstrap("Gameplay cannot start because its World node is missing.")
		return
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
	var autosave_timer := Timer.new()
	autosave_timer.name = "WorldAutosaveTimer"
	autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(save_world_changes)
	add_child(autosave_timer)


func save_world_changes() -> Dictionary:
	var world := get_node_or_null("World") as World
	if world == null:
		return {"ok": false, "error": "Gameplay World node is unavailable."}
	return WorldManager.save_active_world_changes(world)


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
