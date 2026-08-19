extends Node

const SAVE_VERSION := 1
const GENERATOR_VERSION := 1
const WORLDS_DIRECTORY := "user://worlds"
const WORLD_METADATA_FILE := "world.json"
const CHUNKS_DIRECTORY := "chunks"
const GAMEPLAY_SCENE := "res://game/game.tscn"
const MIN_SEED := -2147483648
const MAX_SEED := 2147483647

var active_world_id := ""
var active_world_metadata: Dictionary = {}


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
	metadata["last_played_at"] = _utc_timestamp()
	var write_error := _write_metadata_atomic(world_id, metadata)
	if write_error != OK:
		return _failure("Could not update world metadata.", write_error)

	active_world_id = world_id
	active_world_metadata = metadata.duplicate(true)
	if load_gameplay:
		var scene_error := get_tree().change_scene_to_file(GAMEPLAY_SCENE)
		if scene_error != OK:
			clear_active_world()
			return _failure("Could not load the gameplay scene.", scene_error)
	return {"ok": true, "error": "", "metadata": metadata.duplicate(true)}


func clear_active_world() -> void:
	active_world_id = ""
	active_world_metadata.clear()


func get_active_world_metadata() -> Dictionary:
	return active_world_metadata.duplicate(true)


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


func _write_metadata_atomic(world_id: String, metadata: Dictionary) -> Error:
	var final_path := _metadata_path(world_id)
	var temporary_path := final_path + ".tmp"
	var backup_path := final_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(metadata, "\t") + "\n")
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
