class_name ChunkCollisionBuilder
extends RefCounted


func rebuild(mesh_instance: MeshInstance3D, chunk: Chunk) -> void:
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			child.free()

	if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		mesh_instance.create_trimesh_collision()

		for child in mesh_instance.get_children():
			if child is StaticBody3D:
				child.set_meta("chunk", chunk)
