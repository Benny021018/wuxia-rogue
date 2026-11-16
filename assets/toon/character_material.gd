extends RefCounted

const SURFACE := preload("res://assets/toon/character.gdshader")
const INK := preload("res://assets/toon/ink.gdshader")
const FACE_LIGHT := preload("res://assets/toon/nangong_face_light.png")

## Keep UVs, source colours and skinning on the original surface. The overlay
## remains available to combat feedback. Transparent surfaces retain their alpha mode.
static func apply(mesh: MeshInstance3D, profile: String) -> ShaderMaterial:
	if DisplayServer.get_name() == "headless" or not mesh.mesh:
		return null
	var first: ShaderMaterial
	for i in mesh.mesh.get_surface_count():
		var source := mesh.get_active_material(i) as StandardMaterial3D
		if not source or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		# Nangong's untextured neck shares the body mesh with the robe.
		var slot := "skin" if profile == "robe" and not source.albedo_texture else profile
		var style: Dictionary = Data.toon_materials["cloth" if slot == "robe" else slot]
		var surface := ShaderMaterial.new()
		surface.shader = SURFACE
		surface.set_shader_parameter("base_map", source.albedo_texture)
		surface.set_shader_parameter("base_tint", source.albedo_color)
		surface.set_shader_parameter("surface_kind", int(style.kind))
		surface.set_shader_parameter("shade_tint", Color(style.shade))
		surface.set_shader_parameter("highlight", Color(style.highlight))
		surface.set_shader_parameter("edge", float(style.edge))
		surface.set_shader_parameter("sheen", float(style.sheen))
		if profile == "face":
			surface.set_shader_parameter("face_map", FACE_LIGHT)
		var ink := ShaderMaterial.new()
		ink.shader = INK
		ink.set_shader_parameter("ink", Color(style.ink))
		ink.set_shader_parameter("width_px", float(style.width_px))
		surface.next_pass = ink
		mesh.set_surface_override_material(i, surface)
		if not first:
			first = surface
	return first
