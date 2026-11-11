@tool
extends EditorScenePostImport
## Smart Mesh 的衣料與陰影存於 COLOR_0，匯入 GLB 時保留可發光的標準材質。
func _post_import(scene: Node) -> Object:
	for item in scene.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = item.mesh
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as BaseMaterial3D
			if mat:
				mat.vertex_color_use_as_albedo = true
				if item is MeshInstance3D and item.skin != null:
					var ink := StandardMaterial3D.new()
					ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					ink.cull_mode = BaseMaterial3D.CULL_FRONT
					ink.albedo_color = Color("#242832")
					ink.grow = true
					ink.grow_amount = .002
					mat.next_pass = ink
	return scene
