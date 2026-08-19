extends Node

const SAVE_VERSION := 1
const GENERATOR_VERSION := 1
const WORLDS_DIRECTORY := "user://worlds"
const WORLD_METADATA_FILE := "world.json"
const PLAYER_FILE := "player.json"
const CHUNKS_DIRECTORY := "chunks"
const GAMEPLAY_SCENE := "res://game/game.tscn"
const MIN_SEED := -2147483648
const MAX_SEED := 2147483647

var active_world_id := ""
var active_world_metadata: Dictionary = {}
var active_chunk_overrides: Dictionary = {}
var active_special_block_metadata: Dictionary = {}
var active_player_state: Dictionary = {}


func _ready() -> void:
	ensure_worlds_directory()


func ensure_worlds_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORLDS_DIRECTORY))


func create_world(name: String, seed_text: String = "") -> Dictionary:
	var clean_name := name.strip_edges()
	if clean_name.is_empty():
		return _failure("World name cannot be empty.")

	var seed_result := _parse_or_generate_seed(seed_text)
	if not seed_result["ok"]:
		return seed_result

	var directory_error := ensure_worlds_directory()
	if directory_error != OK:
		return _failure("Could not create the worlds directory.", directory_error)

	var world_id := _generate_world_id()
	var world_directory := _world_directory(world_id)
	var create_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(world_directory.path_join(CHUNKS_DIRECTORY))
	)
	if create_error != OK:
		return _failure("Could not create the world directory.", create_error)

	var now := _utc_timestamp()
	var metadata := {
		"save_version": SAVE_VERSION,
		"generator_version": GENERATOR_VERSION,
		"id": world_id,
		"name": clean_name,
		"seed": seed_result["seed"],
		"created_at": now,
		"last_played_at": now,
	}
	var write_error := _write_metadata_atomic(world_id, metadata)
	if write_error != OK:
		return _failure("Could not write world metadata.", write_error)

	return {"ok": true, "error": "", "metadata": metadata.duplicate(true)}


func list_worlds() -> Array[Dictionary]:
	var worlds: Array[Dictionary] = []
	if ensure_worlds_directory() != OK:
		return worlds

	var directory := DirAccess.open(WORLDS_DIRECTORY)
	if directory == null:
		return worlds

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and _is_safe_world_id(entry):
			var read_result := _read_and_validate_metadata(entry)
			if read_result["ok"]:
				worlds.append(read_result["metadata"])
		entry = directory.get_next()
	directory.list_dir_end()

	worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["last_played_at"]) > str(b["last_played_at"])
	)
	return worlds


func open_world(world_id: String, load_gameplay: bool = true) -> Dictionary:
	if not _is_safe_world_id(world_id):
		return _failure("Invalid world id.")

	var read_result := _read_and_validate_metadata(world_id)
	if not read_result["ok"]:
		return read_result

	var metadata: Dictionary = read_result["metadata"]
	var chunk_data_result := _load_all_chunk_data(world_id)
	var player_state := _load_player_state(world_id)
	metadata["last_played_at"] = _utc_timestamp()
	var write_error := _write_metadata_atomic(world_id, metadata)
	if write_error != OK:
		return _failure("Could not update world metadata.", write_error)

	active_world_id = world_id
	active_world_metadata = metadata.duplicate(true)
	active_chunk_overrides = chunk_data_result["overrides"]
	active_special_block_metadata = chunk_data_result["special"]
	active_player_state = player_state
	if load_gameplay:
		var scene_error := get_tree().change_scene_to_file(GAMEPLAY_SCENE)
		if scene_error != OK:
			clear_active_world()
			return _failure("Could not load the gameplay scene.", scene_error)
	return {"ok": true, "error": "", "metadata": metadata.duplicate(true)}


func clear_active_world() -> void:
	active_world_id = ""
	active_world_metadata.clear()
	active_chunk_overrides.clear()
	active_special_block_metadata.clear()
	active_player_state.clear()


func get_active_world_metadata() -> Dictionary:
	return active_world_metadata.duplicate(true)


func get_active_world_chunk_data() -> Dictionary:
	return {
		"overrides": active_chunk_overrides.duplicate(true),
		"special": active_special_block_metadata.duplicate(true),
	}


func get_active_player_state() -> Dictionary:
	return active_player_state.duplicate(true)


func save_active_world_changes(world: World, player: Player = null) -> Dictionary:
	if active_world_id.is_empty() or active_world_metadata.is_empty():
		return _failure("Cannot save changes without an active world.")
	if world == null:
		return _failure("Cannot save changes without a World instance.")

	var saved_chunks: Array[Vector2i] = []
	var failed_chunks: Array[Dictionary] = []
	for chunk_position in world.get_dirty_chunk_positions():
		var payload := world.get_chunk_save_payload(chunk_position)
		var save_error := _save_chunk_payload(active_world_id, chunk_position, payload)
		if save_error == OK:
			world.mark_chunk_saved(chunk_position)
			_cache_saved_chunk_payload(chunk_position, payload)
			saved_chunks.append(chunk_position)
		else:
			failed_chunks.append({"chunk": chunk_position, "error_code": save_error})

	var player_error := OK
	if player != null:
		var player_payload := player.export_state().duplicate(true)
		player_error = _write_json_atomic(_player_path(active_world_id), player_payload)
		if player_error == OK:
			active_player_state = _normalize_player_payload(player_payload)

	if not failed_chunks.is_empty() or player_error != OK:
		return {
			"ok": false,
			"error": "One or more world files could not be saved.",
			"saved_chunks": saved_chunks,
			"failed_chunks": failed_chunks,
			"player_error": player_error,
		}
	return {
		"ok": true,
		"error": "",
		"saved_chunks": saved_chunks,
		"failed_chunks": [],
		"player_error": OK,
	}


func _cache_saved_chunk_payload(chunk_position: Vector2i, payload: Dictionary) -> void:
	var blocks: Dictionary = payload["blocks"]
	var special: Dictionary = payload["special"]
	if blocks.is_empty():
		active_chunk_overrides.erase(chunk_position)
	else:
		active_chunk_overrides[chunk_position] = blocks.duplicate(true)
	if special.is_empty():
		active_special_block_metadata.erase(chunk_position)
	else:
		active_special_block_metadata[chunk_position] = special.duplicate(true)


func _parse_or_generate_seed(seed_text: String) -> Dictionary:
	var clean_seed := seed_text.strip_edges()
	if clean_seed.is_empty():
		return {"ok": true, "error": "", "seed": _generate_seed()}
	if not clean_seed.is_valid_int():
		return _failure("Seed must be a whole number.")
	var parsed_seed := clean_seed.to_int()
	if parsed_seed < MIN_SEED or parsed_seed > MAX_SEED:
		return _failure("Seed must fit in a signed 32-bit integer.")
	return {"ok": true, "error": "", "seed": parsed_seed}


func _generate_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(4)
	var unsigned_value := (
		int(bytes[0])
		| (int(bytes[1]) << 8)
		| (int(bytes[2]) << 16)
		| (int(bytes[3]) << 24)
	)
	if unsigned_value > MAX_SEED:
		return unsigned_value - 4294967296
	return unsigned_value


func _generate_world_id() -> String:
	var random_bytes := Crypto.new().generate_random_bytes(16)
	var random_hex := ""
	for byte in random_bytes:
		random_hex += "%02x" % int(byte)
	return "w_%x_%s" % [int(Time.get_unix_time_from_system()), random_hex]


func _read_and_validate_metadata(world_id: String) -> Dictionary:
	var metadata_path := _metadata_path(world_id)
	if not FileAccess.file_exists(metadata_path):
		return _failure("World metadata does not exist.", ERR_FILE_NOT_FOUND)

	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return _failure("Could not read world metadata.", FileAccess.get_open_error())
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK or not json.data is Dictionary:
		return _failure("World metadata is corrupt.", ERR_PARSE_ERROR)
	var metadata: Dictionary = json.data
	var validation_error := _validate_metadata(world_id, metadata)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return {"ok": true, "error": "", "metadata": metadata.duplicate(true)}


func _validate_metadata(world_id: String, metadata: Dictionary) -> String:
	for key in ["save_version", "generator_version", "id", "name", "seed", "created_at", "last_played_at"]:
		if not metadata.has(key):
			return "World metadata is missing '%s'." % key
	if not _is_integer_number(metadata["save_version"]):
		return "Invalid save version."
	if int(metadata["save_version"]) != SAVE_VERSION:
		return "Unsupported save version."
	if not _is_integer_number(metadata["generator_version"]):
		return "Invalid generator version."
	if int(metadata["generator_version"]) != GENERATOR_VERSION:
		return "Unsupported generator version."
	if not metadata["id"] is String or metadata["id"] != world_id:
		return "World id does not match its directory."
	if not metadata["name"] is String or metadata["name"].strip_edges().is_empty():
		return "World name cannot be empty."
	if not _is_integer_number(metadata["seed"]):
		return "Invalid world seed."
	var seed_value := int(metadata["seed"])
	if seed_value < MIN_SEED or seed_value > MAX_SEED:
		return "World seed is out of range."
	if (
		not metadata["created_at"] is String
		or not metadata["last_played_at"] is String
		or metadata["created_at"].is_empty()
		or metadata["last_played_at"].is_empty()
	):
		return "Invalid world timestamps."
	metadata["save_version"] = int(metadata["save_version"])
	metadata["generator_version"] = int(metadata["generator_version"])
	metadata["seed"] = seed_value
	return ""


func _load_player_state(world_id: String) -> Dictionary:
	var path := _player_path(world_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not read player save for world '%s'. Using defaults." % world_id)
		return {}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK or not json.data is Dictionary:
		push_warning("Player save for world '%s' is corrupt. Using defaults." % world_id)
		return {}
	var payload: Dictionary = json.data
	if not _is_integer_number(payload.get("save_version")) or int(payload["save_version"]) != SAVE_VERSION:
		push_warning("Player save for world '%s' has an unsupported version. Using defaults." % world_id)
		return {}
	return _normalize_player_payload(payload)


func _normalize_player_payload(payload: Dictionary) -> Dictionary:
	var normalized := {
		"save_version": SAVE_VERSION,
		"selected_hotbar_slot": 0,
		"inventory": _empty_inventory_state(),
	}
	var position: Variant = payload.get("position")
	if (
		position is Array
		and position.size() == 3
		and _is_finite_number(position[0])
		and _is_finite_number(position[1])
		and _is_finite_number(position[2])
	):
		normalized["position"] = Vector3(
			float(position[0]), float(position[1]), float(position[2])
		)
	if _is_finite_number(payload.get("body_yaw")):
		normalized["body_yaw"] = float(payload["body_yaw"])
	if _is_finite_number(payload.get("camera_pitch")):
		normalized["camera_pitch"] = float(payload["camera_pitch"])
	if _is_integer_number(payload.get("selected_hotbar_slot")):
		var selected_slot := int(payload["selected_hotbar_slot"])
		if selected_slot >= 0 and selected_slot < Inventory.HOTBAR_SLOT_COUNT:
			normalized["selected_hotbar_slot"] = selected_slot
	var inventory: Variant = payload.get("inventory")
	if inventory is Array and inventory.size() == Inventory.TOTAL_SLOT_COUNT:
		var slots: Array[Dictionary] = []
		for raw_slot in inventory:
			slots.append(_normalize_inventory_slot(raw_slot))
		normalized["inventory"] = slots
	return normalized


func _normalize_inventory_slot(raw_slot: Variant) -> Dictionary:
	var empty_slot := {"item": ItemRegistry.Item.NONE, "amount": 0}
	if not raw_slot is Dictionary:
		return empty_slot
	if not _is_integer_number(raw_slot.get("item")) or not _is_integer_number(raw_slot.get("amount")):
		return empty_slot
	var item_id := int(raw_slot["item"])
	var amount := int(raw_slot["amount"])
	if item_id <= ItemRegistry.Item.NONE or item_id >= ItemRegistry.Item.size():
		return empty_slot
	var max_stack := ItemRegistry.get_max_stack(item_id)
	if amount <= 0 or amount > max_stack:
		return empty_slot
	return {"item": item_id, "amount": amount}


func _empty_inventory_state() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for _index in Inventory.TOTAL_SLOT_COUNT:
		slots.append({"item": ItemRegistry.Item.NONE, "amount": 0})
	return slots


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _load_all_chunk_data(world_id: String) -> Dictionary:
	var overrides: Dictionary = {}
	var special: Dictionary = {}
	var chunks_path := _world_directory(world_id).path_join(CHUNKS_DIRECTORY)
	var directory := DirAccess.open(chunks_path)
	if directory == null:
		push_warning("Could not open chunk save directory for world '%s'." % world_id)
		return {"overrides": overrides, "special": special}

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.ends_with(".dat"):
			var coordinate_result := _parse_chunk_filename(entry)
			if coordinate_result["ok"]:
				var chunk_position: Vector2i = coordinate_result["chunk"]
				var load_result := _read_chunk_payload(chunks_path.path_join(entry), chunk_position)
				if load_result["ok"]:
					var payload: Dictionary = load_result["payload"]
					if not payload["blocks"].is_empty():
						overrides[chunk_position] = payload["blocks"]
					if not payload["special"].is_empty():
						special[chunk_position] = payload["special"]
				else:
					push_warning("Ignoring corrupt chunk save '%s': %s" % [entry, load_result["error"]])
			else:
				push_warning("Ignoring chunk save with invalid filename '%s'." % entry)
		entry = directory.get_next()
	directory.list_dir_end()
	return {"overrides": overrides, "special": special}


func _read_chunk_payload(path: String, expected_chunk: Vector2i) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open file.", FileAccess.get_open_error())
	var payload: Variant = file.get_var(false)
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return _failure("Could not read Variant payload.", read_error)
	if not payload is Dictionary:
		return _failure("Payload is not a Dictionary.")
	var validation_error := _validate_chunk_payload(payload, expected_chunk)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return {"ok": true, "error": "", "payload": payload}


func _validate_chunk_payload(payload: Dictionary, expected_chunk: Vector2i) -> String:
	for key in ["save_version", "chunk", "blocks", "special"]:
		if not payload.has(key):
			return "Payload is missing '%s'." % key
	if not payload["save_version"] is int or payload["save_version"] != SAVE_VERSION:
		return "Unsupported or invalid save version."
	if not payload["chunk"] is Vector2i or payload["chunk"] != expected_chunk:
		return "Chunk coordinate does not match its filename."
	if not payload["blocks"] is Dictionary or not payload["special"] is Dictionary:
		return "Blocks and special metadata must be Dictionaries."

	var blocks: Dictionary = payload["blocks"]
	for local_position in blocks:
		if not _is_valid_local_position(local_position):
			return "Invalid local block position."
		if not blocks[local_position] is int:
			return "Block id is not an integer."
		var block_id: int = blocks[local_position]
		if block_id < BlockRegistry.Block.AIR or block_id >= BlockRegistry.Block.size():
			return "Block id is outside the registry range."

	var allowed_support_directions: Array[Vector3i] = [
		Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK
	]
	var special: Dictionary = payload["special"]
	for local_position in special:
		if not _is_valid_local_position(local_position):
			return "Invalid special block position."
		if not special[local_position] is Dictionary:
			return "Special block metadata is not a Dictionary."
		var metadata: Dictionary = special[local_position]
		if (
			not metadata.has("support_direction")
			or not metadata["support_direction"] is Vector3i
			or not allowed_support_directions.has(metadata["support_direction"])
		):
			return "Invalid special block support direction."
		if blocks.get(local_position, BlockRegistry.Block.AIR) != BlockRegistry.Block.TORCH:
			return "Special metadata does not reference a saved torch override."
	return ""


func _is_valid_local_position(value: Variant) -> bool:
	if not value is Vector3i:
		return false
	return (
		value.x >= 0 and value.x < ChunkData.SIZE_XZ
		and value.y >= 0 and value.y < ChunkData.HEIGHT
		and value.z >= 0 and value.z < ChunkData.SIZE_XZ
	)


func _parse_chunk_filename(filename: String) -> Dictionary:
	var components := filename.get_basename().split("_", false)
	if components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int():
		return _failure("Invalid chunk filename.")
	return {
		"ok": true,
		"error": "",
		"chunk": Vector2i(components[0].to_int(), components[1].to_int()),
	}


func _save_chunk_payload(
	world_id: String, chunk_position: Vector2i, payload: Dictionary
) -> Error:
	var path := _chunk_path(world_id, chunk_position)
	if payload["blocks"].is_empty() and payload["special"].is_empty():
		if FileAccess.file_exists(path):
			return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return OK
	return _write_chunk_payload_atomic(path, payload.duplicate(true))


func _write_chunk_payload_atomic(path: String, payload: Dictionary) -> Error:
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(payload, false)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return write_error

	var absolute_final := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var had_previous := FileAccess.file_exists(path)
	if had_previous:
		if FileAccess.file_exists(backup_path):
			var remove_error := DirAccess.remove_absolute(absolute_backup)
			if remove_error != OK:
				DirAccess.remove_absolute(absolute_temporary)
				return remove_error
		var backup_error := DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return backup_error

	var replace_error := DirAccess.rename_absolute(absolute_temporary, absolute_final)
	if replace_error != OK:
		if had_previous:
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return replace_error
	if had_previous:
		DirAccess.remove_absolute(absolute_backup)
	return OK


func _write_metadata_atomic(world_id: String, metadata: Dictionary) -> Error:
	return _write_json_atomic(_metadata_path(world_id), metadata)


func _write_json_atomic(final_path: String, payload: Dictionary) -> Error:
	var temporary_path := final_path + ".tmp"
	var backup_path := final_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return write_error

	var absolute_final := ProjectSettings.globalize_path(final_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var had_previous := FileAccess.file_exists(final_path)
	if had_previous:
		if FileAccess.file_exists(backup_path):
			var remove_error := DirAccess.remove_absolute(absolute_backup)
			if remove_error != OK:
				DirAccess.remove_absolute(absolute_temporary)
				return remove_error
		var backup_error := DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return backup_error

	var replace_error := DirAccess.rename_absolute(absolute_temporary, absolute_final)
	if replace_error != OK and had_previous:
		DirAccess.rename_absolute(absolute_backup, absolute_final)
	return replace_error


func _world_directory(world_id: String) -> String:
	return WORLDS_DIRECTORY.path_join(world_id)


func _metadata_path(world_id: String) -> String:
	return _world_directory(world_id).path_join(WORLD_METADATA_FILE)


func _player_path(world_id: String) -> String:
	return _world_directory(world_id).path_join(PLAYER_FILE)


func _chunk_path(world_id: String, chunk_position: Vector2i) -> String:
	return _world_directory(world_id).path_join(CHUNKS_DIRECTORY).path_join(
		"%d_%d.dat" % [chunk_position.x, chunk_position.y]
	)


func _is_safe_world_id(world_id: String) -> bool:
	if world_id.is_empty() or world_id != world_id.get_file():
		return false
	for character in world_id:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


func _is_integer_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value)


func _utc_timestamp() -> String:
	return Time.get_datetime_string_from_system(true, false)


func _failure(message: String, code: Error = FAILED) -> Dictionary:
	return {"ok": false, "error": message, "error_code": code}
