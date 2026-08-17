class_name ChunkCollisionBuilder
extends RefCounted

const SECTION_NODE_PREFIX := "CollisionSection_"


func rebuild(mesh_instance: MeshInstance3D, chunk: Chunk) -> void:
	for section in Chunk.COLLISION_SECTION_COUNT:
		rebuild_section(chunk, section, chunk.get_collision_section_mesh_data(section))


func rebuild_section(chunk: Chunk, section: int, mesh_data: Dictionary) -> void:
	var section_node := get_or_create_section_node(chunk, section)
	for child in section_node.get_children():
		if child is StaticBody3D:
			child.free()

	var source_mesh := chunk.mesher.create_mesh(mesh_data)
	section_node.mesh = source_mesh
	if source_mesh.get_surface_count() > 0:
		section_node.create_trimesh_collision()
		for child in section_node.get_children():
			if child is StaticBody3D:
				child.set_meta("chunk", chunk)
				child.set_meta("collision_section", section)
	section_node.mesh = null


func get_or_create_section_node(chunk: Chunk, section: int) -> MeshInstance3D:
	var node_name := SECTION_NODE_PREFIX + str(section)
	var section_node := chunk.get_node_or_null(node_name) as MeshInstance3D
	if section_node != null:
		return section_node
	section_node = MeshInstance3D.new()
	section_node.name = node_name
	section_node.visible = false
	chunk.add_child(section_node)
	return section_node
