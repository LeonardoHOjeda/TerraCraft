class_name ChunkCollisionBuilder
extends RefCounted

const SECTION_NODE_PREFIX := "CollisionUnit_"


func rebuild(mesh_instance: MeshInstance3D, chunk: Chunk) -> void:
	for section in Chunk.COLLISION_REGION_COUNT:
		rebuild_section(chunk, section, chunk.get_collision_unit_data(section))


func rebuild_section(chunk: Chunk, section: int, mesh_data: Dictionary) -> void:
	var node_name := SECTION_NODE_PREFIX + str(section)
	var existing_body := chunk.get_node_or_null(node_name) as StaticBody3D
	var centers: PackedVector3Array = mesh_data.get("centers", PackedVector3Array())
	var sizes: PackedVector3Array = mesh_data.get("sizes", PackedVector3Array())
	if centers.is_empty():
		if existing_body != null:
			existing_body.free()
		return
	var body := existing_body
	if body == null:
		body = StaticBody3D.new()
		body.name = node_name
		chunk.add_child(body)
	else:
		for child in body.get_children():
			if child is CollisionShape3D:
				child.free()
	body.set_meta("chunk", chunk)
	body.set_meta("collision_region", ChunkMesher.get_collision_region_coords(section))
	for index in centers.size():
		var box := BoxShape3D.new()
		box.size = sizes[index]
		var shape := CollisionShape3D.new()
		shape.name = "Box_%d" % index
		shape.position = centers[index]
		shape.shape = box
		body.add_child(shape)
